import MetalUICore
import MetalUILayout

// `scrollPosition(id:anchor:)` and `scrollTargetLayout()` (item R3-4, rulings `SP-A`...`SP-E`; probe
// `docs/probes/swiftui-scroll-position.swift`).
//
// **Reading.** Content marked by `scrollTargetLayout()` inside a scroller that carries a position binding notes
// its targets during layout (a `ForEach` element, a lazy stack's `ForEach` unit); each target reports its extent
// along the scroller's axis from PREPAINT (`Frame.noteScrollTarget`), and the scroller stores the list in the
// window's `ScrollPositionRegistry`. The binding is written from a wheel event (`Window.scroll` ->
// `didScroll`), and, for a scroll no wheel made (a `scrollTo`), once after the frame that resolved it. It is
// never written from layout, prepaint or paint.
//
// **Writing.** A binding value the registry did not put there is an external write: the scroller's layout
// injects a `scrollTo` for it into the CURRENT frame (`Frame.injectScrollRequest`), so it resolves like any
// `scrollTo` and a redone frame injects it again.

/// A scroller's position binding with the `Binding<ID?>` erased.
struct ScrollPositionBinding {
    var read: @MainActor () -> AnyHashable?
    var write: @MainActor (AnyHashable?) -> Void
    var anchor: UnitPoint?

    @MainActor
    init<ID: Hashable>(_ binding: Binding<ID?>, anchor: UnitPoint?) {
        read = { binding.wrappedValue.map { AnyHashable($0) } }
        write = { value in binding.wrappedValue = value.flatMap { $0.base as? ID } }
        self.anchor = anchor
    }
}

/// One target's extent along the scroll axis, in the scroller's content coordinates.
struct ScrollTargetNote {
    var scroller: GlobalElementID
    var key: AnyHashable
    var start: Double
    var end: Double
}

/// What the window remembers of each position-tracking scroller between frames.
@MainActor
final class ScrollPositionRegistry {
    struct Entry {
        var targets: [ScrollTargetNote]
        var axis: ScrollAxis
        var offset: Double
        var viewport: Double
        var content: Double
        var anchor: UnitPoint?
        var write: @MainActor (AnyHashable?) -> Void
        var read: @MainActor () -> AnyHashable?
        /// A wheel or a `scrollTo` moved the scroller to somewhere this frame's targets may not cover: the frame
        /// that realises the new window reports it once, after paint (`SP-C`).
        var needsReport = false
        /// An animated `scrollTo` is still running: it reports where it lands, not on the way.
        var gliding = false
    }

    private(set) var entries: [GlobalElementID: Entry] = [:]
    /// The value each scroller's binding last held as far as the scroller knows: what it wrote, or what it
    /// scrolled to. A binding that differs is an external write.
    private var known: [GlobalElementID: AnyHashable?] = [:]
    private var touched: Set<GlobalElementID> = []

    /// Counts for the tests: bindings written by this registry.
    private(set) var writes = 0

    func knownValue(of scroller: GlobalElementID) -> AnyHashable?? { known[scroller] }

    func setKnown(_ value: AnyHashable?, for scroller: GlobalElementID) { known[scroller] = .some(value) }

    func update(_ scroller: GlobalElementID, _ entry: Entry) {
        var entry = entry
        if let existing = entries[scroller], existing.needsReport { entry.needsReport = true }
        entries[scroller] = entry
        touched.insert(scroller)
    }

    /// The target a scroller at `offset` reports: with no anchor (or the leading one) the first target whose
    /// extent reaches the viewport's leading edge; with the trailing anchor the last target that starts before
    /// the viewport's end; otherwise the target holding the anchor's point. `nil` when `offset` is outside what
    /// the targets cover (a lazy container's unrealised range) or there are none.
    static func target(in targets: [ScrollTargetNote], offset: Double, viewport: Double, content: Double,
                       anchor: UnitPoint?, axis: ScrollAxis, fresh: Bool = false) -> AnyHashable? {
        guard let first = targets.min(by: { $0.start < $1.start }),
              let last = targets.max(by: { $0.end < $1.end }) else { return nil }
        let fraction = (axis == .vertical ? anchor?.y : anchor?.x) ?? 0
        let reference = offset + fraction * viewport
        // The ends of the content are always covered (a header above the first target, a footer below the last).
        // `fresh`: the targets are those the frame built around this very offset (a lazy window starts above the
        // leading edge), so whatever lies before the first one is a static prelude and the first one leads.
        let low = offset <= 0.5 || fresh ? -Double.infinity : first.start - 0.5
        let high = offset >= content - viewport - 0.5 ? Double.infinity : last.end + 0.5
        guard reference >= low, reference <= high else { return nil }
        let ordered = targets.sorted { ($0.start, $1.end) < ($1.start, $0.end) }   // earlier first, outer before inner
        if fraction <= 0 { return ordered.first { $0.end > reference }?.key }
        if fraction >= 1 { return ordered.last { $0.start < reference }?.key }
        return (ordered.first { $0.start <= reference && reference < $0.end } ?? ordered.first { $0.end > reference })?.key
    }

    /// A wheel moved `scroller` to `offset` (`Window.scroll`): writes the binding if the target there is known
    /// and differs, else flags the entry for the end of the frame that realises it.
    func didScroll(_ scroller: GlobalElementID, offset: Double) {
        guard var entry = entries[scroller] else { return }
        let clamped = min(max(0, offset), max(0, entry.content - entry.viewport))
        entry.offset = clamped
        if let id = Self.target(in: entry.targets, offset: clamped, viewport: entry.viewport,
                                content: entry.content, anchor: entry.anchor, axis: entry.axis) {
            entry.needsReport = false
            entries[scroller] = entry
            report(id, for: scroller, entry)
        } else {
            entry.needsReport = true
            entries[scroller] = entry
        }
    }

    /// After a frame (`Frame.applyScrollResolutions`): reports the scrollers a wheel left unreported and the ones a
    /// `scrollTo` moved last frame, now that a frame has been built around their offsets, and flags the ones
    /// this frame's `scrollTo` moved for the next. Scrollers this frame did not prepaint are kept (`SP-C`).
    func finishFrame(moved: [GlobalElementID: Double]) {
        for scroller in Array(entries.keys) where touched.contains(scroller) {
            guard var entry = entries[scroller], entry.needsReport, !entry.gliding else { continue }
            if let id = Self.target(in: entry.targets, offset: entry.offset, viewport: entry.viewport,
                                    content: entry.content, anchor: entry.anchor, axis: entry.axis, fresh: true) {
                entry.needsReport = false
                entries[scroller] = entry
                report(id, for: scroller, entry)
            }
        }
        for (scroller, offset) in moved {
            guard var entry = entries[scroller] else { continue }
            entry.offset = min(max(0, offset), max(0, entry.content - entry.viewport))
            entry.needsReport = true
            entries[scroller] = entry
        }
        // A scroller replayed by a retained subtree is not prepainted, so an untouched one is not proof it is
        // gone: forget them only when the table has grown past any real window.
        if entries.count > 256 {
            for scroller in Array(entries.keys) where !touched.contains(scroller) {
                entries[scroller] = nil
                known[scroller] = nil
            }
        }
        touched = []
    }

    private func report(_ id: AnyHashable, for scroller: GlobalElementID, _ entry: Entry) {
        guard entry.read() != id else { known[scroller] = .some(id); return }
        known[scroller] = .some(id)
        writes += 1
        entry.write(id)
    }
}

/// A transparent wrapper that marks its content's `ForEach` elements as scroll targets for an enclosing
/// scroller's `scrollPosition(id:)` (`SP-B`). It consumes no cursor index and adds no node and no identity.
public struct ScrollTargetLayout<Content: ElementGroup>: ElementGroup {
    var content: Content
    var isEnabled: Bool

    /// The layout phase's result: the wrapped content's.
    public struct Layout {
        var content: Content.GroupLayout
    }

    /// The prepaint phase's result: the wrapped content's.
    public struct Prepaint {
        var content: Content.GroupPrepaint
    }

    init(content: Content, isEnabled: Bool) {
        self.content = content
        self.isEnabled = isEnabled
    }

    public mutating func requestGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                            pass: inout LayoutPass) -> ([LayoutNodeID], Layout) {
        let enabled = isEnabled
        if enabled { pass.frame.scrollTargetDepth += 1 }
        defer { if enabled { pass.frame.scrollTargetDepth -= 1 } }
        let (nodes, inner) = content.requestGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, Layout(content: inner))
    }

    public mutating func prepaintGroup(layout: inout Layout, pass: inout PrepaintPass) -> Prepaint {
        Prepaint(content: content.prepaintGroup(layout: &layout.content, pass: &pass))
    }

    public mutating func paintGroup(layout: inout Layout, prepaint: inout Prepaint, pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint.content, pass: &pass)
    }
}

extension ScrollTargetLayout: ProposalElementGroup where Content: ProposalElementGroup {
    public mutating func requestProposalGroupLayout(under parent: GlobalElementID?, at cursor: inout Int,
                                                    pass: inout LayoutPass) -> ([ProposalNodeID], Layout) {
        let enabled = isEnabled
        if enabled { pass.frame.scrollTargetDepth += 1 }
        defer { if enabled { pass.frame.scrollTargetDepth -= 1 } }
        let (nodes, inner) = content.requestProposalGroupLayout(under: parent, at: &cursor, pass: &pass)
        return (nodes, Layout(content: inner))
    }
}

extension ElementGroup {
    /// SwiftUI's `scrollTargetLayout(isEnabled:)`: marks this container's `ForEach` elements as the targets
    /// of the enclosing scroll view's ``ScrollView/scrollPosition(id:anchor:)`` (`SP-B`).
    ///
    /// ```swift
    /// ScrollView {
    ///     LazyVStack { ForEach(rows) { RowView($0) } }.scrollTargetLayout()
    /// }
    /// .scrollPosition(id: $topRow)
    /// ```
    ///
    /// The wrapper is layout- and identity-transparent. Every `ForEach` element built inside it, at any
    /// depth, is a target; a nested element and its ancestor are reported by the outermost one that reaches
    /// the viewport's edge. Without it (or without a `scrollPosition(id:)` above) nothing is noted and
    /// the binding is never written.
    public func scrollTargetLayout(isEnabled: Bool = true) -> ScrollTargetLayout<Self> {
        ScrollTargetLayout(content: self, isEnabled: isEnabled)
    }
}

extension ScrollView {
    /// SwiftUI's `scrollPosition(id:anchor:)`: binds the identity of the scroll target at the viewport's
    /// leading edge (`SP-A`).
    ///
    /// - Reading: while the user scrolls, `id` becomes the topmost visible target (the first one whose extent
    ///   reaches the leading edge; with `anchor`, the one holding that point of the viewport). It is written
    ///   from the wheel event itself, never from layout, prepaint or paint.
    /// - Writing: setting `id` scrolls to that target, its leading edge (or `anchor`'s point) at the viewport's,
    ///   the way `ScrollViewProxy.scrollTo` does, including under `withAnimation`. An initial non-nil value
    ///   scrolls on the first frame.
    /// - Targets are the `ForEach` elements under ``ElementGroup/scrollTargetLayout(isEnabled:)``; a `List`
    ///   row is not a target (`SP-E`).
    public func scrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> Self {
        var copy = self
        copy.position = ScrollPositionBinding(id, anchor: anchor)
        return copy
    }
}

extension ProposalScrollView {
    /// ``ScrollView/scrollPosition(id:anchor:)`` for a scroller over proposal content.
    public func scrollPosition<ID: Hashable>(id: Binding<ID?>, anchor: UnitPoint? = nil) -> Self {
        var copy = self
        copy.position = ScrollPositionBinding(id, anchor: anchor)
        return copy
    }
}

extension ScrollPositionBinding {
    /// The scroller's layout half (before its content is built): injects the `scrollTo` for a binding value
    /// the scroller did not put there, and opens the tracking scope.
    @MainActor
    func beginLayout(_ id: GlobalElementID, pass: inout LayoutPass) {
        let registry = pass.frame.scrollRequestQueue.positions
        let current = read()
        let known = registry.knownValue(of: id)
        if known == nil || known! != current {
            if let current {
                pass.frame.injectScrollRequest(
                    ScrollRequest(scope: id, key: current, anchor: anchor ?? .topLeading,
                                  animation: pass.transaction ?? Animation.pendingTransaction))
            }
            pass.frame.pendingPositionKnown[id] = current
        }
        pass.frame.positionTrackingDepth += 1
    }

    /// Closes the scope `beginLayout` opened.
    @MainActor
    func endLayout(pass: inout LayoutPass) {
        pass.frame.positionTrackingDepth -= 1
    }

    /// The scroller's prepaint half: hands the window the targets this frame noted.
    @MainActor
    func finishPrepaint(_ id: GlobalElementID, scroller: ScrollerFrame, since mark: Int, pass: PrepaintPass) {
        let notes = pass.frame.scrollTargetNotes[mark...].filter { $0.scroller == id }
        pass.frame.scrollRequestQueue.positions.update(id, ScrollPositionRegistry.Entry(
            targets: Array(notes), axis: scroller.axis, offset: scroller.offset,
            viewport: scroller.viewportExtent, content: scroller.contentExtent, anchor: anchor,
            write: write, read: read,
            needsReport: false,
            gliding: pass.readState(id, initial: ScrollState()).glide != nil))
    }
}
