// Compiled only under the `SDL` trait (ruling PX-H item 2; GA-I).
#if SDL
import Foundation

/// The debug check of a surface draw's contract (ruling `GA-I`, `MV-F` items 3
/// and 5). `SDLWindowRenderer` brackets each draw with ``beginDraw()`` and
/// ``endDraw()``; the typed layer in `MetalUISDLGPU` reports into it. In a
/// **debug** build a typed `waitForIdle` from inside the draw, and a draw that
/// returns with a typed pass still open, trap naming the contract (both pinned);
/// the async `submitBatch` and `fence.wait` call ``assertNotInsideDraw(_:)`` too;
/// a synchronous draw cannot reach an async verb on its own thread (`GA-O`), so
/// they are pinned through ``enterSimulatedDrawForTesting()`` (`GA-R`). In a
/// release build every method is empty.
///
/// It sees only what goes through the typed layer: a raw SDL call on
/// ``SDLGPUDrawContext/commandBuffer`` is undetectable (SDL3 has no
/// command-buffer state query), and ``SDLGPUDrawContext``'s documentation says so.
package enum SDLGPUWindowGuard {
    #if DEBUG
    private static let lock = NSLock()
    nonisolated(unsafe) private static var drawingThread: Thread?
    nonisolated(unsafe) private static var openPasses = 0
    #endif

    /// A surface draw begins on the calling thread.
    package static func beginDraw() {
        #if DEBUG
        lock.lock(); defer { lock.unlock() }
        drawingThread = Thread.current
        openPasses = 0
        #endif
    }

    /// The draw returned: traps in a debug build if it left a typed pass open.
    package static func endDraw() {
        #if DEBUG
        lock.lock()
        let open = openPasses
        drawingThread = nil
        openPasses = 0
        lock.unlock()
        precondition(open == 0, "a surface draw returned with \(open) pass(es) still open: end every pass "
            + "the draw begins (the SDLGPUDrawContext contract, MV-F item 3)")
        #endif
    }

    /// A typed pass was begun in the frame's own buffer.
    package static func passBegan() {
        #if DEBUG
        lock.lock(); openPasses += 1; lock.unlock()
        #endif
    }

    /// A typed pass in the frame's own buffer was ended.
    package static func passEnded() {
        #if DEBUG
        lock.lock(); openPasses -= 1; lock.unlock()
        #endif
    }

    /// Test hook (ruling `GA-R`, `package`, debug only): marks the **calling
    /// thread** as drawing, as ``beginDraw()`` does, so a test can call a verb
    /// that a synchronous draw cannot reach on its own thread (the async
    /// `submitBatch` and `fence.wait`). Pair with ``leaveSimulatedDrawForTesting()``;
    /// it is never called by the library.
    package static func enterSimulatedDrawForTesting() {
        #if DEBUG
        beginDraw()
        #endif
    }

    /// Test hook: clears what ``enterSimulatedDrawForTesting()`` set.
    package static func leaveSimulatedDrawForTesting() {
        #if DEBUG
        lock.lock(); drawingThread = nil; openPasses = 0; lock.unlock()
        #endif
    }

    /// Whether the calling thread is inside a surface draw (always `false` in
    /// a release build).
    package static var isInsideDraw: Bool {
        #if DEBUG
        lock.lock(); defer { lock.unlock() }
        return drawingThread === Thread.current
        #else
        return false
        #endif
    }

    /// Traps in a debug build when `call` is made from inside a surface draw
    /// on the drawing thread: a draw runs inside the frame's one command buffer
    /// and must not submit, wait or idle (the SDLGPUDrawContext contract, MV-F item 3).
    package static func assertNotInsideDraw(_ call: String) {
        #if DEBUG
        precondition(!isInsideDraw, "\(call) was called inside a surface draw: a draw records into the frame's "
            + "own command buffer and must not submit, cancel, wait on or present it (the SDLGPUDrawContext "
            + "contract, MV-F item 3)")
        #endif
    }
}
#endif
