import Foundation

/// The latency experiment switches (ruling `FP-L`, record 274): environment variables an A/B benchmark sets to
/// change how a frame reaches the screen. **Experiments, not API**: `package`, undocumented outside
/// `docs/frame-timing.md`, free to change or go. Read once, when a window (or its layer) is created; every
/// switch is a stored `Bool` or `Int`, so an unset switch costs one check. Default behaviour is unchanged.
package struct LatencyExperiments: Equatable, Sendable {
    /// `METALUI_EXP_DRAWABLES=2`: `CAMetalLayer.maximumDrawableCount = 2` (2 or 3; anything else is ignored).
    package var drawables: Int?
    /// `METALUI_EXP_LATE_DRAWABLE=1`: acquire `nextDrawable()` after build and paint, before encode.
    package var lateDrawable = false
    /// `METALUI_EXP_IMMEDIATE_INPUT=1`: draw the frame at the end of the input handler when the window was idle.
    package var immediateInput = false
    /// `METALUI_EXP_TRANSACTION=1`: `presentsWithTransaction` with commit, `waitUntilScheduled`, `drawable.present()`.
    package var transaction = false

    package init() {}

    /// Reads the switches from `environment` (a test passes a dictionary; production passes the process's).
    package init(environment: [String: String]) {
        if let value = environment["METALUI_EXP_DRAWABLES"], let count = Int(value), count == 2 || count == 3 {
            drawables = count
        }
        lateDrawable = environment["METALUI_EXP_LATE_DRAWABLE"] == "1"
        immediateInput = environment["METALUI_EXP_IMMEDIATE_INPUT"] == "1"
        transaction = environment["METALUI_EXP_TRANSACTION"] == "1"
    }

    /// The process's switches, read once.
    package static let environment = LatencyExperiments(environment: ProcessInfo.processInfo.environment)

    /// `none`, or the active switches joined by commas (`drawables2,late,immediate,transaction`): the trace
    /// header's `exp=` field.
    package var label: String {
        var parts: [String] = []
        if let drawables { parts.append("drawables\(drawables)") }
        if lateDrawable { parts.append("late") }
        if immediateInput { parts.append("immediate") }
        if transaction { parts.append("transaction") }
        return parts.isEmpty ? "none" : parts.joined(separator: ",")
    }
}

/// A renderer that can defer its drawable (`METALUI_EXP_LATE_DRAWABLE`, `FP-L`). `package`, so
/// `WindowRenderer` (public) is unchanged: `Window` asks with a cast, only when the switch is on.
@MainActor
package protocol LateDrawableWindowRenderer: WindowRenderer {
    /// `beginFrame()` without the drawable: the scale factor and the frame's command buffer only. `nil` when
    /// even that is unavailable (the window stays dirty and retries). A renderer that cannot defer answers as
    /// ``WindowRenderer/beginFrame()`` does.
    func beginFrameDeferringDrawable() -> Float?
    /// Acquires the drawable ``beginFrameDeferringDrawable()`` left out. `false`: none is available; the
    /// frame is abandoned exactly as when ``WindowRenderer/finishFrame(scene:atlas:surfaces:)`` answers `false`.
    func acquireDeferredDrawable() -> Bool
}
