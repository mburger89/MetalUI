import MetalUICore
import MetalUILayout

/// The first of its children whose ideal size fits the space it is offered, SwiftUI's `ViewThatFits`
/// (rulings `VF-A`..`VF-J`, record 217; probe `swiftui-view-that-fits.swift`).
///
/// Each child, in order, is asked its **ideal** size along `axes` (the proposal with those axes made unspecified; the
/// other axis keeps its value) and **fits** when, on every named axis, it is no larger than the proposal (`<=`, probe
/// `H1`). The first child that fits is chosen; **the last is the fallback** when none does. Later children are never
/// asked. The chosen child is then offered the **whole** proposal and the view takes its answer (`I1`, `P1`), so a
/// child that answers more than its ideal still fits and one that answers less than its ideal does not (`W1`, `W2`).
///
/// **Only the chosen child exists in the window's interactive and visible tree** (`VF-C`): the others register no
/// shortcut, hitbox, focus stop, accessibility node, `.onAppear`, `.onChange`, `.task`, geometry callback or
/// presentation, and paint nothing (`K1`, `K4`, `AX0`, `X0`..`X3`). They are still **built** every frame, so a
/// candidate's `@State` is created and survives a switch (`R2`, `VF-E`) and one that is not chosen costs its build.
/// A focused control in a candidate that stops being chosen loses focus and does not regain it (`FO1`, `FO2`, `VF-F`).
///
/// **Divergences** (`docs/divergences.md`, rows 219, 220): a window-level declaration in an unchosen candidate
/// (toolbar items, navigation title) still applies; a later candidate's `@State` seeds on the first frame.
///
/// The view presents its **first** child's default-spacing edge, whichever is chosen (`SP1`, `SP2`, `VF-G`), and a
/// `.layoutPriority` is not passed through from a child (`PR2`). A nested `ViewThatFits` counts as its first child, so
/// nesting does not cascade (`N1`). `ViewThatFits {}` with no children answers zero.
///
/// ```swift
/// ViewThatFits(in: .horizontal) {
///     HStack { Button("Mirror") { … }; Button("Other tool") { … } }
///     Button("More") { … }
/// }
/// ```
public struct ViewThatFits<Content: ProposalElementGroup>: Element {
    /// The children, in preference order.
    public var content: Content
    /// The axes along which a child's ideal must fit.
    public var axes: Axis.Set

    /// A view that shows the first of `content`'s children whose ideal fits along `axes` (SwiftUI's default is both).
    ///
    /// Legacy content enters through `LegacyContent` like every proposal container's (`PE-C`).
    public init(in axes: Axis.Set = [.horizontal, .vertical], @ProposalContentBuilder content: () -> Content) {
        self.axes = axes
        self.content = content()
    }

    public struct Layout {
        var node: LayoutNodeID
        var content: Content.GroupLayout
    }

    public mutating func requestProposalLayout(_ id: GlobalElementID,
                                               pass: inout LayoutPass) -> (ProposalNodeID, Layout) {
        var cursor = 0
        let frame = pass.frame
        let start = frame.tree.nodeCount
        frame.fitDepth += 1
        let (children, contentLayout) = content.requestProposalGroupLayout(under: id, at: &cursor, pass: &pass)
        frame.fitDepth -= 1
        let node = pass.requestNativeFirstFitting(children: children, horizontal: axes.contains(.horizontal),
                                                  vertical: axes.contains(.vertical))
        let candidates = children.map(\.layoutNodeID)
        assert(frame.fitSpanIsContiguous(start: start, candidates: candidates),
               "a ViewThatFits candidate's subtree is not the node range after the previous candidate (VF-D)")
        frame.fitSpans.append(Frame.FitSpan(node: node.layoutNodeID, candidates: candidates, start: start))
        return (node, Layout(node: node.layoutNodeID, content: contentLayout))
    }

    public mutating func prepaint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                                  layout: inout Layout,
                                  pass: inout PrepaintPass) -> Content.GroupPrepaint {
        content.prepaintGroup(layout: &layout.content, pass: &pass)
    }

    public mutating func paint(_ id: GlobalElementID, bounds: Bounds<Pixels>,
                               layout: inout Layout, prepaint: inout Content.GroupPrepaint,
                               pass: inout PaintPass) {
        content.paintGroup(layout: &layout.content, prepaint: &prepaint, pass: &pass)
    }
}

extension ViewThatFits: ProposalElement {}

extension Frame {
    /// Applies the layout's choices (`VF-C`, `VF-D`), between layout and prepaint: every candidate a `ViewThatFits` did
    /// not place becomes elided (a `ViewThatFits` that was itself never placed elides every candidate, and a nested
    /// one inside an unchosen candidate is unplaced), and the lifecycle entries and presentation records that were
    /// noted at build time inside an unchosen candidate are retracted.
    func applyFitChoices() {
        guard !fitSpans.isEmpty else { return }
        // Candidate roots whose subtree was not placed.
        var unchosen: [(low: Int, high: Int)] = []
        for span in fitSpans {
            let choice = tree.firstFittingChoice(span.node)
            var previous = span.start - 1
            for (offset, candidate) in span.candidates.enumerated() {
                let range = (low: previous + 1, high: candidate.index)
                previous = candidate.index
                if choice == offset { continue }
                elidedNodes.insert(candidate)
                unchosen.append(range)
            }
        }
        guard !fitNotes.isEmpty, !unchosen.isEmpty else { return }
        // Adjacent unchosen candidates are one run: a scope over a `Group { A; B }` with neither chosen is retracted.
        unchosen.sort { $0.low < $1.low }
        var runs: [(low: Int, high: Int)] = []
        for range in unchosen {
            if let last = runs.last, range.low <= last.high + 1 {
                runs[runs.count - 1].high = Swift.max(last.high, range.high)
            } else {
                runs.append(range)
            }
        }
        unchosen = runs
        var lifecycleKeys: Set<LifecycleStore.Key> = []
        var presentationKeys: Set<PresentationRecord.Key> = []
        for note in fitNotes where unchosen.contains(where: { note.low >= $0.low && note.high <= $0.high }) {
            switch note.kind {
            case .lifecycle(let key): lifecycleKeys.insert(key)
            case .presentation(let key): presentationKeys.insert(key)
            }
        }
        if !lifecycleKeys.isEmpty { animationStore.lifecycle.retract(lifecycleKeys) }
        if !presentationKeys.isEmpty { presentationRecords.removeAll { presentationKeys.contains($0.key) } }
    }

    /// `VF-D`: candidate `i` is the node range after candidate `i - 1`'s root up to its own root, and every node in the
    /// range descends from the root. A debug assertion (`assert`); a presentation root registered inside a candidate has
    /// no parent and is the one allowed exception.
    func fitSpanIsContiguous(start: Int, candidates: [LayoutNodeID]) -> Bool {
        var previous = start - 1
        for candidate in candidates {
            guard candidate.index > previous else { return false }
            previous = candidate.index
        }
        return true
    }
}
