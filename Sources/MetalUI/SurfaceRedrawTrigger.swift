import Foundation
import MetalUICore
import MetalUIPlatform
import MetalUIScene

/// A handle that redraws one ``GPUSurface`` and nothing else (Alloy gap 5, rulings `TRM-P`…`TRM-T`).
///
/// ```swift
/// let trigger = SurfaceRedrawTrigger()          // owned by the model
/// GPUSurface(redraw: .onDemand, trigger: trigger) { ctx in drawRows(ctx) }
/// // from any thread, when the model changed:
/// trigger.requestRedraw()
/// // a blinking caret: one request, one frame, half a second later
/// trigger.requestRedraw(after: .milliseconds(500))
/// ```
///
/// **A trigger's frame is a surface-only frame** (`TRM-P`): the window re-encodes the last frame's scene and
/// runs the invalidated surfaces' `draw` closures — **no build, no element request, no body re-run**, and a
/// surface that no trigger invalidated is composited as it was. A full frame replaces it, and then forces the
/// same draws, whenever anything else dirtied the window, an animation or timer is running, the scale or size
/// changed, or the glyph atlas was rebuilt.
///
/// **Callable from any thread** (`TRM-Q`): the call records the request under a lock and, once per frame no
/// matter how many calls, hops to the main actor (synchronously when already there). A hundred calls before the
/// next frame draw the surface once. **A trigger whose surface was not painted by the window's last frame does
/// nothing** — it starts no frame and no timer, so a hidden panel costs nothing; the surface paints (and draws)
/// when it returns, as any new target does.
///
/// **Timed requests** (`TRM-R`): ``requestRedraw(after:)`` is measured on the window's frame clock (the
/// timeline's, `TW-A`): the display-link timestamp in a test window, the wall clock in an app. Several pending
/// deadlines for one surface keep the earliest; an immediate request does not cancel a later deadline. The
/// deadline stops with the surface: a frame that does not paint it drops the deadline.
///
/// One trigger serves one surface in one window; give a second surface its own. MetalUI-only (`PB`: SwiftUI's
/// `Canvas` has no such handle).
public final class SurfaceRedrawTrigger: @unchecked Sendable {
    /// What callers asked for since the last drain.
    package struct Pending: Sendable, Equatable {
        /// An immediate request arrived.
        package var immediate = false
        /// The shortest delay asked for.
        package var after: Duration?
    }

    private let lock = NSLock()
    /// Set while the window's last frame painted the surface; calls it from any thread.
    private var wake: (@Sendable () -> Void)?
    private var pending: Pending?
    private var wakeQueued = false

    /// A trigger bound to no surface: its requests do nothing until a ``GPUSurface`` made with it is painted.
    public init() {}

    /// Redraws the surface in the window's next frame, on any thread; repeated calls before that frame make one
    /// draw. Does nothing while the surface is not painted.
    public func requestRedraw() { submit(immediate: true, after: nil) }

    /// Redraws the surface in the first frame at or after `delay` from now on the window's frame clock, on any
    /// thread; the earliest of several pending deadlines wins. Does nothing while the surface is not painted.
    public func requestRedraw(after delay: Duration) { submit(immediate: false, after: delay) }

    private func submit(immediate: Bool, after: Duration?) {
        lock.lock()
        guard let wake else { lock.unlock(); return }
        var entry = pending ?? Pending()
        if immediate { entry.immediate = true }
        if let after { entry.after = entry.after.map { min($0, after) } ?? after }
        pending = entry
        let hops = !wakeQueued
        wakeQueued = true
        lock.unlock()
        if hops { wake() }
    }

    /// Binds the trigger to a painted surface: `wake` runs (on any thread) once per drain.
    package func bind(_ wake: @escaping @Sendable () -> Void) {
        lock.lock(); defer { lock.unlock() }
        self.wake = wake
    }

    /// Unbinds it (the surface was not painted): later requests do nothing, and what was collected is dropped.
    package func unbind() {
        lock.lock(); defer { lock.unlock() }
        wake = nil
        pending = nil
        wakeQueued = false
    }

    /// Whether the last frame painted the surface — test observability.
    package var isBound: Bool {
        lock.lock(); defer { lock.unlock() }
        return wake != nil
    }

    /// Whether a request was made that the window has not drained yet — its hop to the main actor is outstanding
    /// (off Darwin a caller that is not the main thread, such as a test, hops through a `Task`).
    package var hasUndrained: Bool {
        lock.lock(); defer { lock.unlock() }
        return pending != nil
    }

    /// Takes what was requested and re-arms the wake.
    package func drain() -> Pending? {
        lock.lock(); defer { lock.unlock() }
        let taken = pending
        pending = nil
        wakeQueued = false
        return taken
    }
}
