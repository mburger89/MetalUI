import MetalUICore
import MetalUIPlatform

/// Builds the `AccessibilityTree` a window publishes from one frame's records
/// (spec `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`,
/// lanes 1 and 3). Called by `Window` once per drawn frame, and only while a
/// client is active (ruling AB-B).
///
/// **The steps, in order.** Collect one record per id (AB-O); parent each by
/// the nearest recorded ancestor in its portal (AB-C, AB-V); derive actions from
/// live handlers (AB-H); then lane 3's three: **A** distribute a plain
/// container's or wrapper's label and value to its children (AB-T), **B**
/// resolve each node's text, label and value by SwiftUI's static-text rules
/// (AB-F, AB-G), **C** fold a button's non-interactive descendants into its
/// label and value (AB-G); finally map roles (AB-F, AB-L) and copy geometry.
@MainActor
enum AccessibilityTreeBuilder {
    static func build(emissions: [AXEmission],
                      focused: GlobalElementID?,
                      hitboxes: [Hitbox],
                      focusRegistry: FocusRegistry) -> AccessibilityTree {
        // 1. Collect. One record per id, at its first position with its last
        //    content (AB-O): two siblings given the same `.id(_:)` mint one
        //    `GlobalElementID`, and publishing it twice would give one element
        //    two places. **No area filter**: a zero-height labelled node is a
        //    real node (arm R6), and hidden content never recorded.
        var order: [GlobalElementID] = []
        var records: [GlobalElementID: AXEmission] = [:]
        order.reserveCapacity(emissions.count)
        for record in emissions where records.updateValue(record, forKey: record.id) == nil {
            order.append(record.id)
        }

        // 2. Parent. The nearest `GlobalElementID.parent` ancestor that recorded
        //    AND shares the record's portal (AB-C, AB-V); none makes a root. A
        //    second pass over `order`, so a parent recorded after its child
        //    still adopts it, and children land in record order — declaration
        //    order, which the ids alone cannot recover (TB-M).
        var roots: [GlobalElementID] = []
        var children: [GlobalElementID: [GlobalElementID]] = [:]
        for id in order {
            let portal = records[id]!.portal
            var ancestor = id.parent
            while let candidate = ancestor, records[candidate]?.portal != portal {
                ancestor = candidate.parent
            }
            if let parent = ancestor {
                children[parent, default: []].append(id)
            } else {
                roots.append(id)
            }
        }

        // 3. Actions are derived from live handlers, never declared (AB-H). A
        //    press is advertised exactly where a click would find a handler:
        //    the frame's hitboxes, so `allowsHitTesting(false)` removes both.
        //    Focus eligibility is the registry's, not a declaration (AB-J).
        var pressable = Set<GlobalElementID>()
        for hitbox in hitboxes where hitbox.handlers.onClick != nil {
            pressable.insert(hitbox.id)
        }
        let adjustment = ObjectIdentifier(AccessibilityAdjustment.self)
        var state: [GlobalElementID: Resolving] = [:]
        state.reserveCapacity(order.count)
        for (position, id) in order.enumerated() {
            let record = records[id]!
            var actions: AccessibilityActions = []
            if pressable.contains(id) { actions.insert(.press) }
            if focusRegistry.actionHandler(for: id, type: adjustment) != nil {
                actions.formUnion([.increment, .decrement])
            }
            state[id] = Resolving(record: record, position: position, role: record.declared.role,
                                  label: record.declared.label, value: record.declared.value,
                                  actions: actions, isFocusable: focusRegistry.isFocusable(id))
        }

        // A. Distribution (AB-T): top-down, so a chain of wrappers collapses
        //    from the outside in and the outer declaration wins.
        var placed: [GlobalElementID: [GlobalElementID]] = [:]
        let publishedRoots = distribute(roots, label: nil, value: nil,
                                        children: children, state: &state, placed: &placed)

        // B. Text resolution (AB-F, AB-G), on every node that survived A.
        for index in state.indices { state.values[index].resolveText() }

        // C. Combination (AB-G), top-down over the distributed tree.
        combine(publishedRoots, placed: &placed, state: &state)

        // Emit what is reachable from the roots after A and C.
        var nodes: [AccessibilityNodeID: AccessibilityNode] = [:]
        var geometry: [AccessibilityNodeID: AccessibilityGeometry] = [:]
        nodes.reserveCapacity(order.count)
        geometry.reserveCapacity(order.count)
        var pending = publishedRoots
        while let id = pending.popLast() {
            let node = state[id]!
            let kids = placed[id] ?? []
            pending.append(contentsOf: kids)
            let declared = node.record.declared
            let nodeID = AccessibilityNodeID(id)
            nodes[nodeID] = AccessibilityNode(
                role: role(of: node),
                label: node.label,
                value: node.value,
                isSelected: declared.traits.contains(.selected),
                isEnabled: node.record.isEnabled && !declared.traits.contains(.disabled),
                isFocusable: node.isFocusable,
                actions: node.actions,
                children: kids.map(AccessibilityNodeID.init),
                rowCount: declared.logicalCount,
                rowIndex: declared.logicalIndex)
            // Geometry is the record's (its last content), with `order` its
            // FIRST position: the key the AppKit hit test breaks layer ties on,
            // as click dispatch breaks them on registration order (AB-W).
            var placedGeometry = node.record.geometry
            placedGeometry.order = node.position
            geometry[nodeID] = placedGeometry
        }

        // The window's focus after the frame's read-back, if it published.
        let published = focused.flatMap { nodes[AccessibilityNodeID($0)] == nil ? nil : AccessibilityNodeID($0) }
        return AccessibilityTree(roots: publishedRoots.map(AccessibilityNodeID.init), nodes: nodes,
                                 geometry: geometry, focused: published)
    }

    /// One kept record while its label, value and role are being resolved.
    private struct Resolving {
        let record: AXEmission
        let position: Int
        var role: AXRole
        var label: String?
        var value: String?
        let actions: AccessibilityActions
        let isFocusable: Bool

        /// Has a derived action or is focusable: what stops a button folding
        /// its descendants (AB-G).
        var isInteractive: Bool { !actions.isEmpty || isFocusable }

        /// A plain generic node that declared a label or value and has a kept
        /// child (AB-T). **Not clickable, focusable or adjustable**: a click
        /// target is a button and keeps its label (arm R5); focusable and
        /// adjustable are a recorded divergence (SwiftUI distributes from both,
        /// arms C1, C5), because actions route by the node's own id and focus
        /// needs a node to land on. A row hint or a logical count is a list's,
        /// never a wrapper's.
        func distributes(hasChildren: Bool) -> Bool {
            role == .generic && record.declared.logicalCount == nil && record.declared.logicalIndex == nil
                && !record.isClickable && !isFocusable && !actions.contains(.increment)
                && (label != nil || value != nil) && hasChildren
        }

        /// Step B (AB-F, AB-G; arms 1, 3, 5, 8, 10a, 11, R1, R2, R4, R12, R18).
        mutating func resolveText() {
            if let text = record.text {
                if record.isClickable {
                    label = label ?? text                   // a button reads its string
                } else if value == nil {
                    value = label ?? text                   // a static text's label is its value
                    label = nil
                } else {
                    label = label ?? text                   // a value keeps the string as the label
                }
                if role == .generic { role = record.isClickable ? .button : .text }
            } else if role == .generic, record.isClickable {
                role = .button
            }
        }
    }

    /// Step A: returns the ids that take `ids`' places, recording each kept
    /// node's children in `placed`. `label`/`value` are an enclosing
    /// distributor's, and overwrite each node's own (the outer one wins).
    private static func distribute(_ ids: [GlobalElementID], label: String?, value: String?,
                                   children: [GlobalElementID: [GlobalElementID]],
                                   state: inout [GlobalElementID: Resolving],
                                   placed: inout [GlobalElementID: [GlobalElementID]]) -> [GlobalElementID] {
        var result: [GlobalElementID] = []
        result.reserveCapacity(ids.count)
        for id in ids {
            if let label { state[id]!.label = label }
            if let value { state[id]!.value = value }
            let kids = children[id] ?? []
            let node = state[id]!
            if node.distributes(hasChildren: !kids.isEmpty) {
                result.append(contentsOf: distribute(kids, label: node.label, value: node.value,
                                                     children: children, state: &state, placed: &placed))
                state[id] = nil
            } else {
                placed[id] = distribute(kids, label: nil, value: nil,
                                        children: children, state: &state, placed: &placed)
                result.append(id)
            }
        }
        return result
    }

    /// Step C: a button whose descendants are all non-interactive publishes no
    /// children, and takes their label and value contributions where it has
    /// none of its own (AB-G). A button with an interactive descendant keeps
    /// its children and its label, `nil` included (the recorded divergence
    /// from arm R7). Portal content is a root, so it is never a descendant.
    private static func combine(_ ids: [GlobalElementID],
                                placed: inout [GlobalElementID: [GlobalElementID]],
                                state: inout [GlobalElementID: Resolving]) {
        for id in ids {
            let kids = placed[id] ?? []
            if role(of: state[id]!) == .button {
                var descendants: [GlobalElementID] = []
                var stack = Array(kids.reversed())
                var foldable = true
                while let next = stack.popLast() {
                    guard !state[next]!.isInteractive else { foldable = false; break }
                    descendants.append(next)
                    stack.append(contentsOf: (placed[next] ?? []).reversed())
                }
                if foldable {
                    // In tree order: its label, or its value when it has none;
                    // and its value only beside a label (a plain text's value is
                    // its string, which already went to the label).
                    let labels = descendants.compactMap { state[$0]!.label ?? state[$0]!.value }
                    let values = descendants.compactMap { state[$0]!.label == nil ? nil : state[$0]!.value }
                    if state[id]!.label == nil, !labels.isEmpty { state[id]!.label = labels.joined(separator: ", ") }
                    if state[id]!.value == nil, !values.isEmpty { state[id]!.value = values.joined(separator: ", ") }
                    placed[id] = []
                    continue
                }
            }
            combine(kids, placed: &placed, state: &state)
        }
    }

    /// The role map (AB-F, AB-L). A `logicalCount` makes a table **whatever the
    /// declared role** (arm R16): `List` sets `.container` only when nothing
    /// else was declared, so a labelled list is `generic` and would otherwise
    /// publish as a group with no row count. A `logicalIndex` makes a row.
    /// Step B has already turned a clickable `generic` node into a button and a
    /// `generic` text into text. `.updatesFrequently` has no AppKit counterpart
    /// and is dropped.
    private static func role(of node: Resolving) -> AccessibilityRole {
        if node.record.declared.logicalCount != nil { return .table }
        if node.record.declared.logicalIndex != nil { return .row }
        switch node.role {
        case .button: return .button
        case .text: return .staticText
        case .image: return .image
        case .container, .generic: return .group
        }
    }
}
