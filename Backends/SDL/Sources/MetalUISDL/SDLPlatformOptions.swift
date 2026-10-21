// `SDLPlatform.Options` (item S8; rulings `IC-J`, `IC-K`). Compiled only under
// the `SDL` trait; the trait-off stub in `SDLPlatform.swift` declares the same
// names so a call reports the trait's remedy.
#if SDL
import Foundation

extension SDLPlatform {
    /// How an ``SDLPlatform`` opens its windows.
    ///
    /// The options choose what MetalUI owns; the video driver is the
    /// environment's (`SDL_VIDEO_DRIVER`, Mesa llvmpipe, WARP). ``headless`` is
    /// the launch for a CI smoke test of the real window: see `docs/testing.md`,
    /// "A CI smoke test of the real window".
    public struct Options: Sendable, Hashable {
        /// Open every window hidden and never show it. The window and its event
        /// loop still exist, so input, the lifecycle and `.task` run as in
        /// production.
        public var hidesWindows: Bool
        /// Render every window into an offscreen target its pixel size instead of
        /// claiming a swapchain, so frames build and the lifecycle drain runs with
        /// no presented frame (a video driver with no display never yields a
        /// drawable).
        public var rendersOffscreen: Bool
        /// The held single-instance role this platform serves, or `nil` (the
        /// default). With a value the platform delivers each batch a later launch
        /// forwards through ``SDLPlatform/onOpenURLs``, parks it until a handler
        /// exists, and raises a window, as ``SingleInstance`` describes (item S7,
        /// ruling `SN-A`). Take it from ``SingleInstance/claim(id:forwarding:configuration:)``'s
        /// `.primary`, or let ``SDLPlatform/launchingSingleInstance(id:forwarding:options:)``
        /// do both.
        public var singleInstance: SingleInstance?
        /// The application id SDL reports to the desktop, or `nil` (the default).
        ///
        /// On Linux a shell matches a window to its `.desktop` entry by the window's
        /// application id (Wayland `app_id`, X11 `WM_CLASS`), so this should equal the
        /// `.desktop` file's basename and its `StartupWMClass=`, for example
        /// `com.example.MyApp`. The platform sets SDL's `SDL_HINT_APP_ID` before
        /// `SDL_Init` (ruling `AP-A`); the process-wide value applies to every window.
        ///
        /// When `nil`, ``SDLPlatform/launchingSingleInstance(id:forwarding:options:)``
        /// supplies its `id`; with neither, nothing is set (ruling `AP-C`). An empty,
        /// whitespace-only or NUL-bearing value is ignored, never a trap (`AP-D`). An
        /// exported `SDL_APP_ID` environment variable overrides the value (`AP-B`).
        /// macOS and Windows group by the bundle and the AppUserModelID instead:
        /// the value is accepted and has no visible effect there (`AP-E`).
        public var applicationID: String?

        /// - Parameters:
        ///   - hidesWindows: see ``hidesWindows``.
        ///   - rendersOffscreen: see ``rendersOffscreen``.
        ///   - singleInstance: see ``singleInstance``.
        ///   - applicationID: see ``applicationID``.
        public init(hidesWindows: Bool = false, rendersOffscreen: Bool = false,
                    singleInstance: SingleInstance? = nil, applicationID: String? = nil) {
            self.applicationID = applicationID
            self.hidesWindows = hidesWindows
            self.rendersOffscreen = rendersOffscreen
            self.singleInstance = singleInstance
        }

        /// A production launch: windows shown, swapchain rendering.
        public static let `default` = Options()

        /// A launch for CI with no display: windows hidden, offscreen rendering.
        public static let headless = Options(hidesWindows: true, rendersOffscreen: true)

        /// ``applicationID`` when it can be handed to SDL: not empty, not whitespace
        /// only, no NUL byte (ruling `AP-D`).
        var usableApplicationID: String? {
            guard let id = applicationID, !id.utf8.contains(0),
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return id
        }

        /// ``headless`` when the environment variable `METALUI_SDL_HEADLESS` is
        /// exactly `"1"`, ``default`` otherwise.
        ///
        /// ``SDLPlatform`` never reads the variable by itself: the app opts in by
        /// writing `SDLPlatform(options: .headlessIfRequested())`, so one binary
        /// serves a developer and CI.
        ///
        /// - Parameter environment: the variables to read; the process's by default.
        public static func headlessIfRequested(
            environment: [String: String] = ProcessInfo.processInfo.environment
        ) -> Options {
            environment["METALUI_SDL_HEADLESS"] == "1" ? .headless : .default
        }
    }
}
#endif
