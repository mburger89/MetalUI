import MetalUICore
import MetalUILayout

/// SwiftUI's `ScrollViewReader`: hands its content a ``ScrollViewProxy`` whose
/// `scrollTo(_:anchor:)` scrolls to an element inside the reader (plan task 10,
/// part 1, ruling `DD-G`).
///
/// ```swift
/// ScrollViewReader { proxy in
///     ScrollView {
///         Column { ForEach(rows) { row in RowView(row) } }
///     }
///     Box().onClick { proxy.scrollTo(rows[40].id, anchor: .top) }
/// }
/// ```
///
/// **One slot with an identity level of its own** (`DD-G` item 1, `DD-B`'s
/// shape): the reader takes ONE index of its container's cursor space and its
/// content numbers from 0 under that slot, so a sibling after the reader keeps
/// its index and a proxy's reach is exactly the reader's subtree (probe S0–S2:
/// with the key only under ANOTHER reader, a proxy moves nothing).
///
/// **The content closure runs during layout, once per frame**, and what it
/// built is threaded to prepaint and paint in the group layout — `ForEach`'s
/// rule, for the same reason.
public struct ScrollViewReader<Content: ElementGroup>: ElementGroup {
    let content: (ScrollViewProxy) -> Content

    public init(@ElementBuilder content: @escaping (ScrollViewProxy) -> Content) {
        self.content = content
    }

    /// What the content closure built this frame, and its own group layout.
    public struct Layout {
        var content: Content
        var inner: Content.GroupLayout
    }

    /// The slot and the proxy both entries share.
    private func proxy(under parent: GlobalElementID?, at cursor: inout Int,
                       pass: LayoutPass) -> (GlobalElementID, ScrollViewProxy) {
        let slot = GlobalElementID(component: .positional(cursor), parent: parent)
        cursor += 1
        return (slot, ScrollViewProxy(scope: slot, queue: pass.frame.scrollRequestQueue))
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let (slot, proxy) = self.proxy(under: parent, at: &cursor, pass: pass)
        var built = content(proxy)
        var inner = 0
        let (nodes, layout) = built.requestGroupLayout(under: slot, at: &inner, pass: &pass)
        return (nodes, Layout(content: built, inner: layout))
    }

    public mutating func prepaintGroup(layout: inout Layout,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        var built = layout.content
        var inner = layout.inner
        let prepaint = built.prepaintGroup(layout: &inner, pass: &pass)
        layout = Layout(content: built, inner: inner)
        return prepaint
    }

    public mutating func paintGroup(layout: inout Layout,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        var built = layout.content
        var inner = layout.inner
        built.paintGroup(layout: &inner, prepaint: &prepaint, pass: &pass)
        layout = Layout(content: built, inner: inner)
    }
}

extension ScrollViewReader: ProposalElementGroup where Content: ProposalElementGroup {
    /// The typed entry: the same slot and proxy, the typed registration.
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Layout) {
        let (slot, proxy) = self.proxy(under: parent, at: &cursor, pass: pass)
        var built = content(proxy)
        var inner = 0
        let (nodes, layout) = built.requestProposalGroupLayout(under: slot, at: &inner, pass: &pass)
        return (nodes, Layout(content: built, inner: layout))
    }
}

/// What a ``ScrollViewReader`` hands its content: `scrollTo(_:anchor:)`, and
/// nothing else. **No public initialiser**, as SwiftUI's (guard
/// `aScrollViewProxyCannotBeConstructedOutsideTheFramework`).
@MainActor
public struct ScrollViewProxy {
    /// The reader's slot: a request reaches only keys at or under it.
    let scope: GlobalElementID
    /// The window's queue, held weakly — a proxy a caller keeps past its
    /// window's life scrolls nothing rather than keeping the queue alive.
    weak var queue: ScrollRequestQueue?

    init(scope: GlobalElementID, queue: ScrollRequestQueue) {
        self.scope = scope
        self.queue = queue
    }

    /// Scrolls the nearest scroller enclosing the element identified by `id`
    /// inside this proxy's reader (`DD-G` item 2).
    ///
    /// - `id` is compared **by value** (`DD-K`): a `ForEach` element whose key
    ///   equals it, a `List` row whose `datum.id` equals it, or an `.id(_:)`
    ///   element whose `String` name equals it — so `scrollTo("x")` reaches
    ///   `.id("x")` and `scrollTo(10)` does not reach `.id("10")`.
    /// - With an `anchor`, the target's anchor point lands at the viewport's;
    ///   with none, the scroller moves the least distance that shows the target
    ///   (unmoved if it is already visible). Clamped to the content.
    /// - **Call it from input** (a handler), never from a phase. The request
    ///   is resolved by the next frame and shows one frame after that; an id
    ///   that frame does not find does nothing, and the request is dropped.
    public func scrollTo<ID: Hashable>(_ id: ID, anchor: UnitPoint? = nil) {
    }
}

/// One `scrollTo` call, pending until the next frame resolves or drops it.
struct ScrollRequest {
    var scope: GlobalElementID
    var key: AnyHashable
    var anchor: UnitPoint?
}

/// The window's pending `scrollTo` requests (`DD-G` item 3). `Window` owns one
/// and hands it to each `Frame`; a bare `Frame` owns its own, so a request made
/// against it dies with it.
@MainActor
final class ScrollRequestQueue {
    private(set) var pending: [ScrollRequest] = []
    /// Called on every enqueue — `Window` dirties itself here.
    var onEnqueue: (() -> Void)?

    func enqueue(_ request: ScrollRequest) {
        pending.append(request)
        onEnqueue?()
    }

    /// Hands every pending request to the frame that resolves them.
    func take() -> [ScrollRequest] {
        defer { pending = [] }
        return pending
    }
}
