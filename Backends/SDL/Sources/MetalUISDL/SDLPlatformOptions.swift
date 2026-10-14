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

        /// - Parameters:
        ///   - hidesWindows: see ``hidesWindows``.
        ///   - rendersOffscreen: see ``rendersOffscreen``.
        public init(hidesWindows: Bool = false, rendersOffscreen: Bool = false) {
            self.hidesWindows = hidesWindows
            self.rendersOffscreen = rendersOffscreen
        }

        /// A production launch: windows shown, swapchain rendering.
        public static let `default` = Options()

        /// A launch for CI with no display: windows hidden, offscreen rendering.
        public static let headless = Options(hidesWindows: true, rendersOffscreen: true)

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
