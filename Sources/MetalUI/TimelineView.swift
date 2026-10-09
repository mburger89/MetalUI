import Foundation
import MetalUICore
import MetalUILayout

// MARK: - `TimelineView` (rulings `KF-K`, `KF-L`, `KF-T`)
//
// STUB (lane B red): the content is built with the caller's parent and cursor
// and the store's (stub) context.

/// What a `TimelineView`'s content is built with — SwiftUI's
/// `TimelineViewDefaultContext` (ruling `KF-K` item 1).
public struct TimelineViewDefaultContext: Sendable {
    /// How often the view is being rebuilt — SwiftUI's cadence. **Always
    /// `.live` in MetalUI** (T5; `KF-K` item 1): a window never lowers it.
    public enum Cadence: Comparable, Sendable {
        /// Every scheduled date.
        case live
        /// About once a second.
        case seconds
        /// About once a minute.
        case minutes
    }

    /// The date this build shows: the frame's date for `.animation`, the
    /// schedule's last entry not after now otherwise (T4).
    public let date: Date
    /// The rebuild cadence (always `.live`).
    public let cadence: Cadence

    init(date: Date, cadence: Cadence) {
        self.date = date
        self.cadence = cadence
    }
}

/// The layout of a `TimelineView`: the content this build evaluated and its
/// layout, carried to prepaint and paint.
public struct TimelineViewLayout<Content: ElementGroup> {
    var content: Content
    var layout: Content.GroupLayout
}

/// Content rebuilt on a schedule — SwiftUI's `TimelineView` (rulings `KF-K`,
/// `KF-L`). **Identity- and layout-transparent** (`KF-L`): the content keeps
/// the ids it would have without the view, so wrapping content in one resets
/// no `@State`.
public struct TimelineView<Schedule: TimelineSchedule, Content: ProposalElementGroup>: ProposalElementGroup {
    /// SwiftUI's nested name for the context (`KF-T`).
    public typealias Context = TimelineViewDefaultContext

    let schedule: Schedule
    let content: (TimelineViewDefaultContext) -> Content

    /// A view that builds `content` with the date `schedule` gives it, in
    /// every build, rebuilding when the schedule's next date arrives.
    public init(_ schedule: Schedule,
                @ProposalContentBuilder content: @escaping (TimelineViewDefaultContext) -> Content) {
        self.schedule = schedule
        self.content = content
    }

    /// Evaluates the content with this build's context and lays it out with
    /// the caller's parent and cursor.
    public mutating func requestGroupLayout(under parent: GlobalElementID?,
                                            at cursor: inout Int,
                                            pass: inout LayoutPass)
        -> ([LayoutNodeID], TimelineViewLayout<Content>) {
        let store = pass.frame.animationStore.timeline
        let (context, _) = store.context(owner: .child(of: parent, at: cursor, name: nil), schedule: schedule,
                                         timestamp: pass.frame.timestamp, stateTable: pass.frame.stateTable)
        var built = content(context)
        let (nodes, layout) = built.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, TimelineViewLayout(content: built, layout: layout))
    }

    /// The typed entry: a line-for-line copy of the untyped one, pinned on its
    /// own (spec test T14).
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?,
                                                    at cursor: inout Int,
                                                    pass: inout LayoutPass)
        -> ([ProposalNodeID], TimelineViewLayout<Content>) {
        let store = pass.frame.animationStore.timeline
        let (context, _) = store.context(owner: .child(of: parent, at: cursor, name: nil), schedule: schedule,
                                         timestamp: pass.frame.timestamp, stateTable: pass.frame.stateTable)
        var built = content(context)
        let (nodes, layout) = built.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, TimelineViewLayout(content: built, layout: layout))
    }

    /// Prepaints the content this build evaluated.
    public mutating func prepaintGroup(layout: inout TimelineViewLayout<Content>,
                                       pass: inout PrepaintPass) -> Content.GroupPrepaint {
        layout.content.prepaintGroup(layout: &layout.layout, pass: &pass)
    }

    /// Paints the content this build evaluated.
    public mutating func paintGroup(layout: inout TimelineViewLayout<Content>,
                                    prepaint: inout Content.GroupPrepaint,
                                    pass: inout PaintPass) {
        layout.content.paintGroup(layout: &layout.layout, prepaint: &prepaint, pass: &pass)
    }
}
