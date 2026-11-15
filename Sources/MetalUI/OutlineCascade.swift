import MetalUICore

// ⌥→ and ⌥← over a content list's `DisclosureGroup(isExpanded:)` tree (outline lane 5, rulings `OG-E`, `P-K4`, `P-K5`,
// `P-C1`; divergence 1086).
//
// SwiftUI writes every descendant's `isExpanded` binding in the turn of the key (the recorded 5-deep chain wrote four in
// one turn, `P-K4d`), including rows never built. MetalUI cannot do that from the input handler: a group's content is a
// closure the app wrote, evaluating it needs a layout pass (its components' `@State`, its environment), and a binding
// may only be written from input, never from layout (`RW-I`). So the key writes nothing but a REQUEST (`pending`, in the
// list's own state entry), and the next build carries it out:
//
//  - **expand** (⌥→): the group and every group below it is built as expanded for that build (`direction(for:)`), so the
//    whole subtree is flattened at once, and each group that was not expanded queues its own write
//    (`LifecycleStore.enqueue`, the drain `CodeView` uses, `CV-K`). The window runs the writes after the build, in ONE turn,
//    and builds again inside the same `beginFrame` (`LC-E`), so the presented frame already holds the bindings the
//    writes set: every descendant `isExpanded` is written in one turn, as SwiftUI does.
//  - **collapse** (⌥←): the group is built as it is; every group below it that is expanded queues a write of `false`.
//    Only groups the flatten reaches are written: a group under an already collapsed child keeps its own state.
//
// What differs from SwiftUI is where the write happens (after the build, not in the key's handler) and that the
// presented frame never shows the unexpanded state: divergence 1086.

/// The requests of a content list's cascades and the state a build carries them out in. A namespace over a few statics,
/// as `ListRowChrome.isActive` is: set around one list's layout, never read elsewhere.
@MainActor
enum OutlineCascade {
    /// What a list's layout hands the flatten while it runs.
    struct Context {
        /// The group ids with a pending cascade, and its direction (`true` expands).
        var pending: [GlobalElementID: Bool]
        /// Queues a write to run after the build, in the turn the window drains its events (`owner` is the group).
        var queue: @MainActor (_ owner: GlobalElementID, _ write: @escaping @MainActor () -> Void) -> Void
        /// Records a request for the next build (input time).
        var request: @MainActor (_ group: GlobalElementID, _ expand: Bool) -> Void
    }

    private(set) static var context: Context?
    /// The direction every group below the one being flattened is forced to, `nil` outside a cascade.
    private(set) static var forcing: Bool?

    static func whileActive<R>(_ context: Context, _ body: () -> R) -> R {
        let outer = self.context
        self.context = context
        defer { self.context = outer }
        return body()
    }

    /// The cascade `group` is flattened under: its own request, else the one inherited from an ancestor's.
    static func direction(for group: GlobalElementID) -> Bool? {
        context?.pending[group] ?? forcing
    }

    /// Runs `body` with every group inside it forced to `direction`.
    static func forcing<R>(_ direction: Bool?, _ body: () -> R) -> R {
        let outer = forcing
        forcing = direction
        defer { forcing = outer }
        return body()
    }
}
