import MetalUICore
import MetalUIPlatform

/// One build's answer: the tree, and what `Window` keeps beside it to dispatch
/// a request (plan task 12 part 2, lane 2, spec §5–§6).
struct AccessibilityBuild {
    var tree: AccessibilityTree
    /// Where a press (or an adjustment) on a published node that has no handler
    /// of its own goes, first entry first: a combined node's interactive
    /// descendants in tree order (`IX-V` item 2), and a child a plain
    /// container distributed its declared action to → that container (`IX-Y`
    /// item 1, arm A5).
    var redirects: [GlobalElementID: [GlobalElementID]] = [:]
    /// What each published custom action runs, index for index with the node's
    /// `AccessibilityNode.customActions`.
    var customActions: [GlobalElementID: [AccessibilityCustomActionTarget]] = [:]
    /// Whether the tree was built under modal isolation (`IX-X` item 3): a
    /// request naming an id it does not contain is then refused (`IX-Z` item 3).
    var isolatedOut = false
}

/// What one published custom action runs (`IX-Y` item 2, `IX-V` item 2).
enum AccessibilityCustomActionTarget: Equatable {
    /// The node's own `AccessibilityNamedAction` handler, with this name.
    case named(String)
    /// A combined node's interactive descendant's press.
    case press(GlobalElementID)
}

/// Builds the `AccessibilityTree` a window publishes from one frame's records
/// (spec `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`,
/// lanes 1 and 3; plan task 12 part 2, spec `2026-09-29-accessibility-design.md`
/// §5). Called by `Window` once per drawn frame, and only while a client is
/// active (ruling AB-B).
///
/// **The steps, in order.** Collect one record per id (AB-O); parent each by
/// the nearest recorded ancestor in its portal (AB-C, AB-V); **isolate** a
/// modal subtree (`IX-X` item 3); derive actions from live handlers (AB-H,
/// `IX-Y`, `IX-Z`); then: **A** distribute a plain container's or wrapper's
/// label, value, hint, identifier, header and selected traits and declared
/// action to its children (AB-T, `IX-W`, `IX-X`, `IX-Y`), dropping an
/// `.ignore` element's children (`IX-V`); **B** resolve each node's text, label
/// and value by SwiftUI's static-text rules (AB-F, AB-G); **C** fold a button's
/// non-interactive descendants into its label and value (AB-G); **`.combine`**
/// each combining element, innermost first (`IX-V` item 2); finally map roles
/// and traits (AB-F, AB-L, `IX-X`) and copy geometry.
@MainActor
enum AccessibilityTreeBuilder {
    /// The tree alone — every caller but `Window`, which keeps the rest of
    /// `buildResult`'s answer to dispatch a request.
    static func build(emissions: [AXEmission],
                      focused: GlobalElementID?,
                      hitboxes: [Hitbox],
                      pressOnly: [GlobalElementID: @MainActor () -> Void] = [:],
                      focusRegistry: FocusRegistry,
                      menus: Set<GlobalElementID> = []) -> AccessibilityTree {
        buildResult(emissions: emissions, focused: focused, hitboxes: hitboxes, pressOnly: pressOnly,
                    focusRegistry: focusRegistry, menus: menus).tree
    }

    static func buildResult(emissions: [AXEmission],
                            focused: GlobalElementID?,
                            hitboxes: [Hitbox],
                            pressOnly: [GlobalElementID: @MainActor () -> Void] = [:],
                            focusRegistry: FocusRegistry,
                            menus: Set<GlobalElementID> = []) -> AccessibilityBuild {
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

        // Modal isolation (`IX-X` item 3; SwiftUI M1–M3): a record declaring
        // `.isModal` — the one with the greatest `(layer, order)` of several —
        // is the only root, and everything outside its subtree is dropped.
        var result = AccessibilityBuild(tree: .empty)
        let modal = order.enumerated()
            .filter { records[$0.element]!.declared.declarations.traits.contains(.isModal) }
            .max { (records[$0.element]!.geometry.layer, $0.offset) < (records[$1.element]!.geometry.layer, $1.offset) }?
            .element
        if let modal {
            result.isolatedOut = true
            var kept = Set<GlobalElementID>()
            var pending = [modal]
            while let next = pending.popLast() {
                guard kept.insert(next).inserted else { continue }
                pending.append(contentsOf: children[next] ?? [])
            }
            roots = [modal]
            order = order.filter(kept.contains)
        }

        // 3. Actions are derived from live handlers, never declared (AB-H). A
        //    press is advertised where a click would find a handler — the
        //    frame's hitboxes — and, since plan task 12 part 2, where only
        //    `allowsHitTesting(false)` kept one from finding it (`IX-Z` item 1,
        //    arm B6), and where `accessibilityAction(_:)` registered one
        //    (`IX-Y` item 1, A1 — behind the one disabled gate, A7). Focus
        //    eligibility is the registry's, not a declaration (AB-J). A named
        //    action publishes its names only while its handler is registered.
        var pressable = Set<GlobalElementID>()
        for hitbox in hitboxes where hitbox.handlers.onClick != nil {
            pressable.insert(hitbox.id)
        }
        pressable.formUnion(pressOnly.keys)
        let adjustment = ObjectIdentifier(AccessibilityAdjustment.self)
        let defaultAction = ObjectIdentifier(AccessibilityDefaultAction.self)
        let namedAction = ObjectIdentifier(AccessibilityNamedAction.self)
        var state: [GlobalElementID: Resolving] = [:]
        state.reserveCapacity(order.count)
        for (position, id) in order.enumerated() {
            let record = records[id]!
            let declarations = record.declared.declarations
            var actions: AccessibilityActions = []
            if pressable.contains(id) || focusRegistry.actionHandler(for: id, type: defaultAction) != nil {
                actions.insert(.press)
            }
            if focusRegistry.actionHandler(for: id, type: adjustment) != nil {
                actions.formUnion([.increment, .decrement])
            }
            // A context menu a client may open (menus, `MN-G` item 2): from the
            // frame's declared menus, not a hitbox — still advertised under
            // `allowsHitTesting(false)` (`MN-U`) — and, as every action, not by
            // a disabled node.
            if menus.contains(id), record.isEnabled {
                actions.insert(.showMenu)
            }
            let names = focusRegistry.actionHandler(for: id, type: namedAction) != nil ? declarations.actionNames : []
            state[id] = Resolving(record: record, position: position, role: record.declared.role,
                                  label: record.declared.label, value: record.declared.value,
                                  hint: declarations.hint, identifier: declarations.identifier,
                                  actions: actions, isFocusable: focusRegistry.isFocusable(id),
                                  hasDeclaredAction: record.declaresAction,
                                  customActions: names, customTargets: names.map { .named($0) })
        }

        // A. Distribution (AB-T): top-down, so a chain of wrappers collapses
        //    from the outside in and the outer declaration wins.
        var placed: [GlobalElementID: [GlobalElementID]] = [:]
        let publishedRoots = distribute(roots, Inherited(), children: children, state: &state,
                                        placed: &placed, redirects: &result.redirects)

        // B. Text resolution (AB-F, AB-G), on every node that survived A.
        for index in state.indices { state.values[index].resolveText() }

        // C. Combination (AB-G), top-down over the distributed tree.
        combine(publishedRoots, placed: &placed, state: &state)

        // `.combine` (`IX-V` item 2), innermost first, so a combined element
        // inside another contributes its joined text (E10).
        for id in publishedRoots { combineElements(under: id, placed: &placed, state: &state, build: &result) }

        // Emit what is reachable from the roots after A and C.
        var nodes: [AccessibilityNodeID: AccessibilityNode] = [:]
        var geometry: [AccessibilityNodeID: AccessibilityGeometry] = [:]
        nodes.reserveCapacity(order.count)
        geometry.reserveCapacity(order.count)
        // A row a client may select directly (`IX-AA` item 1): a `.row` whose
        // published parent is a list with a registered `AccessibilityRowSelection`
        // handler — a `List(selection:)` that is enabled and not hidden. The
        // emit order visits a parent before its children.
        let rowSelection = ObjectIdentifier(AccessibilityRowSelection.self)
        var selectableRows = Set<GlobalElementID>()
        var pending = publishedRoots
        while let id = pending.popLast() {
            let node = state[id]!
            var kids = (placed[id] ?? []).map(AccessibilityNodeID.init)
            pending.append(contentsOf: placed[id] ?? [])
            if focusRegistry.actionHandler(for: id, type: rowSelection) != nil {
                selectableRows.formUnion(placed[id] ?? [])
            }
            let declared = node.record.declared
            let nodeID = AccessibilityNodeID(id)
            // Geometry is the record's (its last content), with `order` its
            // FIRST position: the key the AppKit hit test breaks layer ties on,
            // as click dispatch breaks them on registration order (AB-W).
            var placedGeometry = node.record.geometry
            placedGeometry.order = node.position
            // `.contain` over a text leaf (E9): a group, and the text as one
            // synthesized static-text child no request resolves.
            if declared.declarations.childBehavior == .contain, let text = node.record.text {
                let contained = AccessibilityNodeID(ContainedText(id: id))
                kids = [contained]
                nodes[contained] = AccessibilityNode(role: .staticText, value: text,
                                                     isEnabled: node.record.isEnabled)
                geometry[contained] = placedGeometry
            }
            let publishedRole = publishedRole(of: node)
            nodes[nodeID] = AccessibilityNode(
                role: publishedRole,
                label: node.label,
                value: node.value,
                isSelected: declared.traits.contains(.selected) || declared.selectionHint
                    || node.traits.contains(.isSelected),
                isEnabled: node.record.isEnabled && !declared.traits.contains(.disabled),
                isFocusable: node.isFocusable,
                actions: node.actions,
                children: kids,
                rowCount: declared.logicalCount,
                rowIndex: declared.logicalIndex,
                hint: node.hint,
                identifier: node.identifier,
                customActions: node.customActions,
                isSelectable: publishedRole == .row && selectableRows.contains(id))
            if !node.customTargets.isEmpty { result.customActions[id] = node.customTargets }
            geometry[nodeID] = placedGeometry
        }

        // The window's focus after the frame's read-back, if it published —
        // so a focus outside a modal subtree publishes none.
        let published = focused.flatMap { nodes[AccessibilityNodeID($0)] == nil ? nil : AccessibilityNodeID($0) }
        result.tree = AccessibilityTree(roots: publishedRoots.map(AccessibilityNodeID.init), nodes: nodes,
                                        geometry: geometry, focused: published)
        return result
    }

    /// One kept record while its label, value and role are being resolved.
    private struct Resolving {
        let record: AXEmission
        let position: Int
        var role: AXRole
        var label: String?
        var value: String?
        var hint: String?
        var identifier: String?
        var actions: AccessibilityActions
        let isFocusable: Bool
        /// Declared `accessibilityAction(_:)`, or had one distributed to it
        /// (A5): read as a button, labelled by its text (A1, A7).
        var hasDeclaredAction: Bool
        /// The `.isHeader`/`.isSelected` traits a container distributed (T9).
        var inheritedTraits: AccessibilityTraits = []
        var customActions: [String]
        var customTargets: [AccessibilityCustomActionTarget]
        /// A combined node's role, the first interactive descendant's, or a
        /// static text (`IX-V` item 2).
        var combinedRole: AccessibilityRole?

        init(record: AXEmission, position: Int, role: AXRole, label: String?, value: String?,
             hint: String?, identifier: String?, actions: AccessibilityActions, isFocusable: Bool,
             hasDeclaredAction: Bool, customActions: [String],
             customTargets: [AccessibilityCustomActionTarget]) {
            self.record = record
            self.position = position
            self.role = role
            self.label = label
            self.value = value
            self.hint = hint
            self.identifier = identifier
            self.actions = actions
            self.isFocusable = isFocusable
            self.hasDeclaredAction = hasDeclaredAction
            self.customActions = customActions
            self.customTargets = customTargets
        }

        var declarations: AXDeclarations { record.declared.declarations }

        /// The node's declared traits plus what a container distributed to it.
        var traits: AccessibilityTraits { declarations.traits.union(inheritedTraits) }

        /// Has a derived action or is focusable: what stops a button folding
        /// its descendants (AB-G), and what `.combine` takes a role from.
        var isInteractive: Bool { !actions.isEmpty || isFocusable }

        /// A plain generic node that declared something to hand down and has a
        /// kept child (AB-T; `IX-W` item 2, `IX-X` item 2, `IX-Y` item 1). **Not
        /// clickable, focusable or adjustable**: a click target is a button and
        /// keeps its label (arm R5); focusable and adjustable are a recorded
        /// divergence (SwiftUI distributes from both, arms C1, C5), because
        /// actions route by the node's own id and focus needs a node to land on.
        /// A row hint or a logical count is a list's, never a wrapper's. **Nor
        /// an element that declared a child behaviour** (`.contain` keeps its
        /// label, E5), **a modal one**, or one whose role a trait sets.
        func distributes(hasChildren: Bool) -> Bool {
            let handsDown = label != nil || value != nil || hint != nil || identifier != nil
                || !traits.intersection([.isHeader, .isSelected]).isEmpty || hasDeclaredAction
            return role == .generic && record.declared.logicalCount == nil && record.declared.logicalIndex == nil
                && !record.isClickable && !isFocusable && !actions.contains(.increment)
                && declarations.childBehavior == nil && declarations.addedTraits
                    .intersection([.isModal, .isButton, .isLink, .isImage, .isStaticText]).isEmpty
                && handsDown && hasChildren
        }

        /// Step B (AB-F, AB-G; arms 1, 3, 5, 8, 10a, 11, R1, R2, R4, R12, R18).
        /// A button — clickable, or declaring an action (A1, A7) — reads its
        /// string as its label; so do a heading and a link (T1, T6) and the
        /// `.isButton` trait (T2). A `.contain` element's text is its
        /// synthesized child's (E9), not its own.
        mutating func resolveText() {
            let isButtonLike = record.isClickable || hasDeclaredAction
            if let text = record.text, declarations.childBehavior != .contain {
                if isButtonLike || !traits.intersection([.isButton, .isHeader, .isLink]).isEmpty {
                    label = label ?? text                   // a button reads its string
                } else if value == nil {
                    value = label ?? text                   // a static text's label is its value
                    label = nil
                } else {
                    label = label ?? text                   // a value keeps the string as the label
                }
                if role == .generic { role = isButtonLike ? .button : .text }
            } else if role == .generic, isButtonLike {
                role = .button
            }
        }
    }

    /// What an enclosing distributor hands down (AB-T): each field overwrites
    /// a node's own, so the outer declaration wins.
    private struct Inherited {
        var label: String?
        var value: String?
        var hint: String?
        var identifier: String?
        var traits: AccessibilityTraits = []
        /// The distributor whose declared action a child's press runs (A5).
        var action: GlobalElementID?
    }

    /// Step A: returns the ids that take `ids`' places, recording each kept
    /// node's children in `placed`. An `.ignore` element keeps none (E1, E2,
    /// E12).
    private static func distribute(_ ids: [GlobalElementID], _ inherited: Inherited,
                                   children: [GlobalElementID: [GlobalElementID]],
                                   state: inout [GlobalElementID: Resolving],
                                   placed: inout [GlobalElementID: [GlobalElementID]],
                                   redirects: inout [GlobalElementID: [GlobalElementID]]) -> [GlobalElementID] {
        var result: [GlobalElementID] = []
        result.reserveCapacity(ids.count)
        for id in ids {
            if let label = inherited.label { state[id]!.label = label }
            if let value = inherited.value { state[id]!.value = value }
            if let hint = inherited.hint { state[id]!.hint = hint }
            if let identifier = inherited.identifier { state[id]!.identifier = identifier }
            state[id]!.inheritedTraits.formUnion(inherited.traits)
            if let action = inherited.action {
                state[id]!.actions.insert(.press)
                state[id]!.hasDeclaredAction = true
                redirects[id] = [action]
            }
            let kids = state[id]!.declarations.childBehavior == .ignore ? [] : (children[id] ?? [])
            let node = state[id]!
            if node.distributes(hasChildren: !kids.isEmpty) {
                let handed = Inherited(label: node.label, value: node.value, hint: node.hint,
                                       identifier: node.identifier,
                                       traits: node.traits.intersection([.isHeader, .isSelected]),
                                       action: node.hasDeclaredAction ? id : nil)
                result.append(contentsOf: distribute(kids, handed, children: children, state: &state,
                                                     placed: &placed, redirects: &redirects))
                state[id] = nil
            } else {
                placed[id] = distribute(kids, Inherited(), children: children, state: &state,
                                        placed: &placed, redirects: &redirects)
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
    ///
    /// **A check box and a radio button fold exactly as a button does** (ruling
    /// `DD-U` item 2; TA0, PA1, PA2 read kids=0): a `Toggle`'s and a `Picker`
    /// option's label content becomes their label. **An incrementor and a
    /// radio group fold partially** (`DD-U` item 3): their non-interactive
    /// descendants' text becomes the label (when none is declared) and is not
    /// published, and their interactive descendants — a stepper's arrow
    /// halves, a picker's options — stay as children, each then combined in
    /// its own right. So a `Stepper`'s or `Picker`'s title labels the control
    /// itself, where SwiftUI publishes it as a sibling static text beside an
    /// unlabelled control (divergence 82).
    ///
    /// **It reads the role before any trait** (`IX-X` item 2): a clickable
    /// element with `.isButton` removed folds as a button and only then
    /// publishes as a group, keeping the folded label (T3p).
    private static func combine(_ ids: [GlobalElementID],
                                placed: inout [GlobalElementID: [GlobalElementID]],
                                state: inout [GlobalElementID: Resolving]) {
        for id in ids {
            let kids = placed[id] ?? []
            switch role(of: state[id]!) {
            case .button, .checkBox, .radioButton:
                var descendants: [GlobalElementID] = []
                var stack = Array(kids.reversed())
                var foldable = true
                while let next = stack.popLast() {
                    guard !state[next]!.isInteractive else { foldable = false; break }
                    descendants.append(next)
                    stack.append(contentsOf: (placed[next] ?? []).reversed())
                }
                if foldable {
                    takeLabelAndValue(from: descendants, into: id, state: &state)
                    placed[id] = []
                    continue
                }
            case .incrementor, .radioGroup:
                // Walk in tree order: an interactive node — or a control that
                // is not interactive only because it is disabled (a disabled
                // picker's options publish DISABLED, PA4) — is kept, its subtree
                // untouched; any other node contributes and is dropped, and its
                // own children are walked in its place.
                var kept: [GlobalElementID] = []
                var folded: [GlobalElementID] = []
                var stack = Array(kids.reversed())
                while let next = stack.popLast() {
                    let node = state[next]!
                    let isControl = node.isInteractive || (role(of: node) != .staticText && role(of: node) != .group)
                    if isControl {
                        kept.append(next)
                    } else {
                        folded.append(next)
                        stack.append(contentsOf: (placed[next] ?? []).reversed())
                    }
                }
                takeLabelAndValue(from: folded, into: id, state: &state, value: false)
                placed[id] = kept
                combine(kept, placed: &placed, state: &state)
                continue
            default:
                break
            }
            combine(kids, placed: &placed, state: &state)
        }
    }

    /// The fold's contribution, in tree order: each descendant's label, or its
    /// value when it has none, joined into `id`'s label where it has none; and
    /// (with `value`) each labelled descendant's value into `id`'s value (a
    /// plain text's value is its string, which already went to the label). A
    /// partial fold takes no value: an incrementor's value is its own number.
    private static func takeLabelAndValue(from descendants: [GlobalElementID], into id: GlobalElementID,
                                          state: inout [GlobalElementID: Resolving], value: Bool = true) {
        let labels = descendants.compactMap { state[$0]!.label ?? state[$0]!.value }
        let values = descendants.compactMap { state[$0]!.label == nil ? nil : state[$0]!.value }
        if state[id]!.label == nil, !labels.isEmpty { state[id]!.label = labels.joined(separator: ", ") }
        if value, state[id]!.value == nil, !values.isEmpty { state[id]!.value = values.joined(separator: ", ") }
    }

    /// `.combine` (`IX-V` item 2, `IX-AI`; SwiftUI E3, E6–E8, E10, E11,
    /// E14–E21, E18p), post-order. In tree order, a non-interactive descendant
    /// contributes its label (or value) and, when labelled, its value, and is
    /// walked into; no interactive descendant is walked into, and only the
    /// LEAD among them (see the branch) contributes its label, when it carries
    /// no value (E6 `A, B`; E7 `A` beside the toggle's `1`). With none
    /// interactive the node is a static text, the join resolved as a static
    /// text's (a value, or the label where a descendant carried a value); with
    /// one or more, the interactive descendants merge as the branch says. A
    /// declared label replaces the join (E8). Children are dropped.
    private static func combineElements(under id: GlobalElementID,
                                        placed: inout [GlobalElementID: [GlobalElementID]],
                                        state: inout [GlobalElementID: Resolving],
                                        build: inout AccessibilityBuild) {
        for child in placed[id] ?? [] {
            combineElements(under: child, placed: &placed, state: &state, build: &build)
        }
        guard state[id]!.declarations.childBehavior == .combine else { return }
        // Tree order: a non-interactive descendant's text, or the slot of an
        // interactive one (not walked into), whose label is decided after.
        enum Entry { case text(String), control(GlobalElementID) }
        var entries: [Entry] = []
        var values: [String] = []
        var interactive: [GlobalElementID] = []
        var stack = Array((placed[id] ?? []).reversed())
        while let next = stack.popLast() {
            let node = state[next]!
            if node.isInteractive {
                entries.append(.control(next))
                interactive.append(next)
            } else {
                if let text = node.label ?? node.value { entries.append(.text(text)) }
                if node.label != nil, let value = node.value { values.append(value) }
                stack.append(contentsOf: (placed[next] ?? []).reversed())
            }
        }
        // Mixed kinds MERGE rather than copy one child (`IX-AI`; SwiftUI E6,
        // E7, E14–E21, E18p). The LEAD — whose label joins when it carries no
        // value, whose actions the node takes, and whom a press reaches — is
        // the first child that presses, else the first that is not adjustable
        // (a slider is skipped, E18p; a text field yields to a button, E20).
        // The role is the highest-ranked child's, ties to the first; the value
        // the LAST child's that carries one; an adjustable child adds its
        // increment and decrement, and an adjustment reaches it (`Window`);
        // only a child that presses is a custom action. `redirects` lists the
        // lead first, so a press reaches it.
        let pressing = interactive.filter { state[$0]!.actions.contains(.press) }
        let adjustable = interactive.filter { isAdjustable(state[$0]!) }
        let leadID = pressing.first ?? interactive.first(where: { !isAdjustable(state[$0]!) }) ?? interactive.first
        let texts = entries.compactMap { entry -> String? in
            switch entry {
            case .text(let text): return text
            case .control(let child):
                guard child == leadID, state[child]!.value == nil else { return nil }
                return state[child]!.label
            }
        }
        let joined = state[id]!.label ?? (texts.isEmpty ? nil : texts.joined(separator: ", "))
        if let leadID {
            let lead = state[leadID]!
            let roles = interactive.map { publishedRole(of: state[$0]!) }
            var combinedRole = roles[0]
            for role in roles.dropFirst() where combinedRoleRank(role) > combinedRoleRank(combinedRole) {
                combinedRole = role
            }
            state[id]!.combinedRole = combinedRole
            state[id]!.actions.formUnion(lead.actions)
            for child in adjustable {
                state[id]!.actions.formUnion(state[child]!.actions.intersection([.increment, .decrement]))
            }
            state[id]!.label = joined
            state[id]!.value = state[id]!.value
                ?? interactive.last(where: { state[$0]!.value != nil }).flatMap { state[$0]!.value }
            state[id]!.customActions += pressing.map { state[$0]!.label ?? state[$0]!.value ?? "" }
            state[id]!.customTargets += pressing.map { .press($0) }
            build.redirects[id] = [leadID] + interactive.filter { $0 != leadID }
        } else {
            state[id]!.combinedRole = .staticText
            let value = state[id]!.value ?? (values.isEmpty ? nil : values.joined(separator: ", "))
            if let value {
                state[id]!.label = joined
                state[id]!.value = value
            } else {
                state[id]!.label = nil
                state[id]!.value = joined
            }
        }
        placed[id] = []
    }

    /// A child `.combine` treats as a slider rather than a pressable control
    /// (`IX-AI`): it adjusts and does not press.
    private static func isAdjustable(_ node: Resolving) -> Bool {
        !node.actions.intersection([.increment, .decrement]).isEmpty && !node.actions.contains(.press)
    }

    /// A combined node's role rank (`IX-AI`): SwiftUI ranks a slider over a
    /// checkbox over a button over a text field whatever their order
    /// (E15–E21). The incrementor beside the slider and the radio button
    /// beside the checkbox are MetalUI's choice, unprobed; every other role
    /// ranks with the text field.
    private static func combinedRoleRank(_ role: AccessibilityRole) -> Int {
        switch role {
        case .slider, .incrementor: return 3
        case .checkBox, .radioButton: return 2
        case .button: return 1
        default: return 0
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
        case .textField: return .textField
        case .textArea: return .textArea
        case .checkBox: return .checkBox
        case .radioButton: return .radioButton
        case .radioGroup: return .radioGroup
        case .slider: return .slider
        case .incrementor: return .incrementor
        case .container, .generic: return .group
        }
    }

    /// The published role: a combined node's, else `role(of:)` with the traits
    /// applied (`IX-X` item 2; SwiftUI T1–T11). **Each trait sets the role
    /// only**: a removed `.isButton` turns a button into a group (T3p — after
    /// step C folded it); `.isStaticText` makes a static text of a button, a
    /// group or a text; `.isImage` an image and `.isLink` a link of a group or
    /// a text (a link of a button too); `.isButton` a button and `.isHeader` a
    /// heading of a group or a text — so a header on a button stays a button
    /// (T11). `.isModal`, `.isSelected` and `.updatesFrequently` set no role.
    private static func publishedRole(of node: Resolving) -> AccessibilityRole {
        if let combined = node.combinedRole { return combined }
        var role = role(of: node)
        let traits = node.traits
        let plain: [AccessibilityRole] = [.group, .staticText]
        if node.declarations.removedTraits.contains(.isButton), role == .button { role = .group }
        if traits.contains(.isStaticText), plain.contains(role) || role == .button { role = .staticText }
        if traits.contains(.isImage), plain.contains(role) { role = .image }
        if traits.contains(.isLink), plain.contains(role) || role == .button { role = .link }
        if traits.contains(.isButton), plain.contains(role) { role = .button }
        if traits.contains(.isHeader), plain.contains(role) { role = .heading }
        return role
    }
}

/// The key of the static-text child a `.contain` element over a text leaf
/// publishes (`IX-V` item 3, arm E9): a key no request resolves, because its
/// base is not a `GlobalElementID`, so the child has no actions.
struct ContainedText: Hashable {
    let id: GlobalElementID
}
