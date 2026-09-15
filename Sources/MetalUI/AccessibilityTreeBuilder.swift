import MetalUICore
import MetalUIPlatform

/// Builds the `AccessibilityTree` a window publishes from one frame's records
/// (spec `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`,
/// lane 1). Called by `Window` once per drawn frame, and only while a client is
/// active (ruling AB-B).
///
/// **Lane 1's algorithm.** Lane 3 inserts label distribution, text resolution
/// and button combination between hierarchy and roles; until then a node says
/// exactly what it declared, plus what its live handlers make it.
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
        var roots: [AccessibilityNodeID] = []
        var children: [GlobalElementID: [AccessibilityNodeID]] = [:]
        for id in order {
            let portal = records[id]!.portal
            var ancestor = id.parent
            while let candidate = ancestor, records[candidate]?.portal != portal {
                ancestor = candidate.parent
            }
            if let parent = ancestor {
                children[parent, default: []].append(AccessibilityNodeID(id))
            } else {
                roots.append(AccessibilityNodeID(id))
            }
        }

        // 3. Actions are derived from live handlers, never declared (AB-H). A
        //    press is advertised exactly where a click would find a handler:
        //    the frame's hitboxes, so `allowsHitTesting(false)` removes both.
        var pressable = Set<GlobalElementID>()
        for hitbox in hitboxes where hitbox.handlers.onClick != nil {
            pressable.insert(hitbox.id)
        }
        let adjustment = ObjectIdentifier(AccessibilityAdjustment.self)

        var nodes: [AccessibilityNodeID: AccessibilityNode] = [:]
        var geometry: [AccessibilityNodeID: AccessibilityGeometry] = [:]
        nodes.reserveCapacity(order.count)
        geometry.reserveCapacity(order.count)
        for (position, id) in order.enumerated() {
            let record = records[id]!
            let declared = record.declared
            var actions: AccessibilityActions = []
            if pressable.contains(id) { actions.insert(.press) }
            if focusRegistry.actionHandler(for: id, type: adjustment) != nil {
                actions.formUnion([.increment, .decrement])
            }
            let nodeID = AccessibilityNodeID(id)
            nodes[nodeID] = AccessibilityNode(
                role: role(of: record),
                label: declared.label,
                value: declared.value,
                isSelected: declared.traits.contains(.selected),
                isEnabled: record.isEnabled && !declared.traits.contains(.disabled),
                // 4. Focus eligibility is the registry's, not a declaration.
                isFocusable: focusRegistry.isFocusable(id),
                actions: actions,
                children: children[id] ?? [],
                rowCount: declared.logicalCount)
            // 6. Geometry is the record's (its last content), with `order` its
            //    FIRST position: the key the AppKit hit test breaks layer ties
            //    on, as click dispatch breaks them on registration order (AB-W).
            var placed = record.geometry
            placed.order = position
            geometry[nodeID] = placed
        }

        // 4. The window's focus after the frame's read-back, if it published.
        let published = focused.flatMap { records[$0] == nil ? nil : AccessibilityNodeID($0) }
        return AccessibilityTree(roots: roots, nodes: nodes, geometry: geometry,
                                 focused: published)
    }

    /// 5. The role map. A `logicalCount` makes a table **whatever the declared
    ///    role** (AB-L, arm R16): `List` sets `.container` only when nothing
    ///    else was declared, so a labelled list is `generic` and would otherwise
    ///    publish as a group with no row count. A clickable `generic` node is a
    ///    button. `.updatesFrequently` has no AppKit counterpart and is dropped.
    private static func role(of record: AXEmission) -> AccessibilityRole {
        if record.declared.logicalCount != nil { return .table }
        switch record.declared.role {
        case .button: return .button
        case .text: return .staticText
        case .image: return .image
        case .container: return .group
        case .generic: return record.isClickable ? .button : .group
        }
    }
}
