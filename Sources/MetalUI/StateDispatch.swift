import MetalUICore

/// The element input dispatch is running a handler for, so an aliased `@State`
/// or `@Environment` box can serve that handler's own occurrence (plan task 8,
/// ruling ID-F).
///
/// **The shape it resolves.** One element VALUE placed twice (`Row { p; p }`)
/// shares one `State.Box`, because the box is a class and the struct is
/// copied. Each occurrence binds the box to its own slot in every phase, and a
/// handler registered by either occurrence captures the same box — so by the
/// time a click arrives, the box's `slotID` is whichever occurrence bound
/// last. Since ID-F the box also remembers every slot it served in that
/// generation (`State.Box.occurrences`), and each dispatch site names the
/// element it is dispatching to here, so the box can pick the occurrence whose
/// element is the owner **or an ancestor of it** (a `Component`'s `@State`
/// written from a `Box` inside its body).
///
/// **Sites** (each sets the owner around exactly one handler call):
/// `Window.dispatchClick` (the hit id), `dispatchKey` (each chain id whose
/// handler runs), `dispatchAction` (each chain id whose handler runs),
/// `Window.handleAccessibilityRequest`'s press and adjust (the node's id), and
/// the text-input path's edit and submit callbacks (the field's id).
///
/// **Outside dispatch the owner is `nil`**, and an aliased box reads and writes
/// its last-bound slot, as before — divergence 71 (a timer, a task or a direct
/// call; SwiftUI keeps each occurrence's own storage there too, probe S5).
@MainActor
enum StateDispatch {
    /// The element whose handler is running, or `nil` outside input dispatch.
    static private(set) var owner: GlobalElementID?

    /// Runs `body` with `owner` set to `id`, restoring the previous owner after
    /// (a handler that synchronously dispatches again nests correctly).
    static func dispatching<R>(to id: GlobalElementID, _ body: () throws -> R) rethrows -> R {
        let previous = owner
        owner = id
        defer { owner = previous }
        return try body()
    }

    /// Of `candidates` — element ids an aliased box was bound under this
    /// generation — the one that is the owner or its nearest ancestor, or `nil`
    /// when nothing is dispatching or none matches. Nearest first: the walk
    /// starts at the owner and climbs.
    static func resolve(among candidates: [GlobalElementID]) -> Int? {
        var cursor = owner
        while let ancestor = cursor {
            if let index = candidates.firstIndex(of: ancestor) { return index }
            cursor = ancestor.parent
        }
        return nil
    }
}
