import Foundation
import Observation

// C14 lane 2 (`IV-B`…`IV-D`, `IV-L`): the window's content memos.

/// A liveness token for one memo session — `RedrawSentinel`'s trick, one per
/// memoized component: read inside the session, written (serial bumped first)
/// before the next evaluation so the previous session fires and is removed.
@Observable
final class ContentMemoToken {
    var tick: Int = 0
}

/// The window's `Component.equatable()` memos (`IV-B`), hosted on `StateTable`.
/// **STUB (red-first commit): evaluates every getter, memoizes nothing.**
@MainActor
package final class ContentMemoStore {
    package var isEnabled = true
    package private(set) var evaluations = 0
    package private(set) var skips = 0
    package private(set) var refusals = 0
    package private(set) var lastEvaluations = 0
    package private(set) var lastSkips = 0
    package private(set) var lastRefusals = 0
    package private(set) var armedSessions = 0
    package var entryCount: Int { 0 }
    var markDirty: (@MainActor () -> Void)?

    func noteRefusal() { refusals += 1 }

    func materialize<C: Component & Equatable>(_ component: C, id: GlobalElementID,
                                               stateIDs: [GlobalElementID], table: StateTable,
                                               getter: () -> C.Content) -> C.Content {
        evaluations += 1
        return getter()
    }

    func endFrame() {
        lastEvaluations = evaluations; lastSkips = skips; lastRefusals = refusals
        evaluations = 0; skips = 0; refusals = 0
    }
}
