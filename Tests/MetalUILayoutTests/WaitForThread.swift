import Foundation

/// Blocks until `thread` has finished, polling each millisecond. Synchronous
/// on purpose: the exit tests that spawn a large-stack thread call it from
/// their async body, where `Thread.sleep` is unavailable, and `usleep` — what
/// they used before — does not exist on Windows (roadmap item 5).
func waitUntilFinished(_ thread: Thread) {
    while !thread.isFinished { Thread.sleep(forTimeInterval: 0.001) }
}
