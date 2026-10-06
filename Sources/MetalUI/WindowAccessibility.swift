import MetalUICore
import MetalUIPlatform

/// A window's accessibility state: whether a client is present, what was last
/// published, and the counters the bridge's cost claims are made in (rulings
/// AB-B, AB-M).
///
/// **Nothing here runs per frame while inactive except one `Int` and one `Bool`
/// store** (the record count and the retry flag, AB-X rule 3).
/// `Window` builds each frame with `collectsAccessibility: isActive`, so an
/// inactive frame records nothing, and `frameDidRender` returns before its
/// autoclosure is evaluated.
@MainActor
final class WindowAccessibility {
    /// Set by the first `.activate` and never cleared (AB-B).
    private(set) var isActive = false

    /// The tree the platform was last handed. Starts `.empty`, which is also
    /// what a platform exposes before any publish, so an active window whose
    /// tree is empty publishes nothing.
    private(set) var lastPublished = AccessibilityTree.empty

    /// The last build's dispatch tables (plan task 12 part 2, spec §6): a
    /// combined node's and a distributed action's redirects, what each custom
    /// action runs, and whether the tree was built under modal isolation.
    /// Written with every build, published or not — a build that published
    /// nothing new still answers the frame's handlers.
    private(set) var lastRedirects: [GlobalElementID: [GlobalElementID]] = [:]
    private(set) var lastCustomActions: [GlobalElementID: [AccessibilityCustomActionTarget]] = [:]
    private(set) var lastIsolatedOut = false

    /// Trees built: one per drawn frame while active. Test observable.
    private(set) var buildCount = 0

    /// Trees handed to the platform: only those that differed from
    /// `lastPublished`, geometry included (AB-M). Test observable.
    private(set) var publishCount = 0

    /// The last drawn frame's record count, **written every frame, active or
    /// not**. Test observable, and the only counter that sees a frame recording
    /// while inactive: the build is an autoclosure, so `buildCount` cannot.
    private(set) var lastEmissionCount = 0

    /// Marks a client present. `true` only on the first call: the caller dirties
    /// the window exactly once.
    func activate() -> Bool {
        guard !isActive else { return false }
        isActive = true
        return true
    }

    /// Whether the previous drawn frame asked for an accessibility retry.
    private var lastFrameRetried = false

    /// Called by `Window.drawFrameIfNeeded` after every drawn frame. Returns
    /// whether the window should be dirtied for one more frame.
    ///
    /// **`retry` is honoured only when the previous drawn frame did not ask**
    /// (ruling AB-X rule 3): a `List` whose scroller never measures a viewport
    /// asks on every frame, and answering every time would be a display link
    /// that never pauses. One extra frame per run of asking frames. `retry` is
    /// `false` on every frame that did not collect, so an inactive window never
    /// retries.
    func frameDidRender(emissionCount: Int,
                        retry: Bool,
                        _ build: @autoclosure () -> AccessibilityBuild,
                        to platformWindow: any PlatformWindow) -> Bool {
        lastEmissionCount = emissionCount
        let dirties = retry && !lastFrameRetried
        lastFrameRetried = retry
        guard isActive else { return dirties }
        let result = build()
        let built = result.tree
        lastRedirects = result.redirects
        lastCustomActions = result.customActions
        lastIsolatedOut = result.isolatedOut
        buildCount += 1
        guard built != lastPublished else { return dirties }
        lastPublished = built
        publishCount += 1
        platformWindow.publishAccessibilityTree(built)
        return dirties
    }
}

extension Window {
    /// Answers a platform accessibility request (`PlatformWindow.onAccessibilityRequest`)
    /// through the dispatch input already uses, against the **last drawn
    /// frame's** records — there is no frame in flight when a request arrives,
    /// exactly as there is none for a click (rulings AB-B, AB-H, AB-I, AB-J).
    ///
    /// An id that is not a `GlobalElementID`, or that the last frame did not
    /// register for the request, is refused with `false` and changes nothing.
    func handleAccessibilityRequest(_ request: AccessibilityRequest) -> Bool {
        switch request {
        case .activate:
            // Dirty only the first time: every later frame then collects.
            if accessibility.activate() { setNeedsRedraw() }
            return true
        case .press(let node):
            guard isOfferedUnderIsolation(node), let id = node.base as? GlobalElementID else { return false }
            if let chosen = pressAlertButton(id) { return chosen }   // the drawn alert is modal (SV-J item 4)
            if let chosen = pressMenuRow(id) { return chosen }   // the in-window menu (MN-F item 4)
            return press(id, redirectsLeft: 4)
        case .increment(let node):
            guard isOfferedUnderIsolation(node) else { return false }
            return adjust(node, .increment)
        case .decrement(let node):
            guard isOfferedUnderIsolation(node) else { return false }
            return adjust(node, .decrement)
        case .focus(let node):
            // `Window.focus` itself validates nothing; the refusal here is what
            // keeps a client from focusing an element that ignores keystrokes.
            guard isOfferedUnderIsolation(node), let id = node.base as? GlobalElementID,
                  lastFocusRegistry.isFocusable(id) else { return false }
            focus(id)
            return true
        case .customAction(let node, let index):
            // What the build said the node's `index`-th custom action runs
            // (plan task 12 part 2, `IX-Y` item 2, `IX-V` item 2): its own named
            // handler, or a combined node's descendant's press.
            guard isOfferedUnderIsolation(node), let id = node.base as? GlobalElementID,
                  let targets = accessibility.lastCustomActions[id], targets.indices.contains(index)
            else { return false }
            switch targets[index] {
            case .named(let name):
                guard let handler = lastFocusRegistry.actionHandler(
                    for: id, type: ObjectIdentifier(AccessibilityNamedAction.self)) else { return false }
                StateDispatch.dispatching(to: id) {   // ID-F: the element declaring it
                    handler(AccessibilityNamedAction(name: name))
                }
                setNeedsRedraw()
                return true
            case .press(let target):
                return press(target, redirectsLeft: 4)
            }
        case .select(let row):
            guard isOfferedUnderIsolation(row) else { return false }
            // The row's table in the last published tree (`IX-AA` item 1).
            guard let table = accessibility.lastPublished.nodes.first(where: {
                $0.value.role == .table && $0.value.children.contains(row)
            })?.key else { return false }
            return selectRows(table, [row])
        case .selectRows(let table, let rows):
            guard isOfferedUnderIsolation(table) else { return false }
            return selectRows(table, rows)
        case .showMenu(let node):
            // A recorded context menu (`MN-G` item 2), at the element's
            // bottom-leading corner; refused for a node without one (C11n).
            guard isOfferedUnderIsolation(node), let id = node.base as? GlobalElementID,
                  let record = lastContextMenus[id] else { return false }
            let opened = openContextMenu(of: id, record)
            if opened { setNeedsRedraw() }
            return opened
        }
    }

    /// Divergence 95 (plan task 12 part 2, `IX-Z` item 3): when the last
    /// published tree was built under modal isolation, an id it does not
    /// contain — one a client cached before the modal appeared — is refused.
    /// SwiftUI's held element still presses (M5); refusing is `AB-H`'s side:
    /// never let a client operate what the user is not offered.
    private func isOfferedUnderIsolation(_ node: AccessibilityNodeID) -> Bool {
        !accessibility.lastIsolatedOut || accessibility.lastPublished.nodes[node] != nil
    }

    /// An accessibility press on `id`, in the order `IX-Z` item 2 rules: a
    /// declared `accessibilityAction(_:)` (A4 — it replaces the click's press,
    /// G6 — and a tap's); a redirect (a combined node's first interactive
    /// descendant, E6/E14, or the container that distributed its action, A5);
    /// the LAST hitbox for the id with a click handler, as click dispatch ranks
    /// a later registration above an earlier one; then, where
    /// `allowsHitTesting(false)` withheld the hitbox from an enabled `onClick`,
    /// that handler (`IX-Z` item 1: SwiftUI presses there, arm B6 — a click
    /// still finds nothing). Each runs through `runClick`, so a press keeps no
    /// modifiers (`DD-Z` item 9) and its focus request (`IX-Z` item 2).
    /// `redirectsLeft` bounds a chain of redirects (a distributed action
    /// redirects once per nesting level).
    private func press(_ id: GlobalElementID, redirectsLeft: Int) -> Bool {
        if let declared = lastFocusRegistry.actionHandler(
            for: id, type: ObjectIdentifier(AccessibilityDefaultAction.self)) {
            runClick({ declared(AccessibilityDefaultAction()) }, on: id, modifiers: [])
            setNeedsRedraw()
            return true
        }
        if redirectsLeft > 0, let target = accessibility.lastRedirects[id]?.first {
            return press(target, redirectsLeft: redirectsLeft - 1)
        }
        guard let onClick = lastHitboxes.last(where: { $0.id == id && $0.handlers.onClick != nil })?
            .handlers.onClick ?? lastAccessibilityPressOnly[id] else { return false }
        runClick(onClick, on: id, modifiers: [])
        setNeedsRedraw()
        return true
    }

    /// Runs the list's OWN `AccessibilityRowSelection` handler with `rows`
    /// (`IX-AA` item 1). Refused unless `table` is a published table and every
    /// row one of its published children, and unless the last frame registered
    /// the handler — a list without `selection:`, a disabled list and a hidden
    /// one register none. The list decides what the rows mean (a single list
    /// ignores two, LA4); a handled request answers `true`, as a press does.
    private func selectRows(_ table: AccessibilityNodeID, _ rows: [AccessibilityNodeID]) -> Bool {
        guard let tableNode = accessibility.lastPublished.nodes[table], tableNode.role == .table,
              rows.allSatisfy(tableNode.children.contains),
              let id = table.base as? GlobalElementID,
              let handler = lastFocusRegistry.actionHandler(
                  for: id, type: ObjectIdentifier(AccessibilityRowSelection.self)) else { return false }
        let rowIDs = rows.compactMap { $0.base as? GlobalElementID }
        guard rowIDs.count == rows.count else { return false }
        StateDispatch.dispatching(to: id) {   // ID-F: the list itself
            handler(AccessibilityRowSelection(rows: rowIDs))
        }
        setNeedsRedraw()
        return true
    }

    /// Runs the element's OWN `AccessibilityAdjustment` handler, never an
    /// ancestor's (AB-I).
    private func adjust(_ node: AccessibilityNodeID,
                        _ direction: AccessibilityAdjustmentDirection) -> Bool {
        guard var id = node.base as? GlobalElementID else { return false }
        // A combined node adjusts its first descendant that takes an
        // adjustment (`IX-V` item 2, `IX-AI`: beside a button, the slider,
        // SwiftUI E17/E18p), when it has no handler of its own.
        let takesAdjustment = { (candidate: GlobalElementID) in
            self.lastFocusRegistry.actionHandler(
                for: candidate, type: ObjectIdentifier(AccessibilityAdjustment.self)) != nil
        }
        if !takesAdjustment(id), let target = accessibility.lastRedirects[id]?.first(where: takesAdjustment) {
            id = target
        }
        guard let handler = lastFocusRegistry.actionHandler(
                  for: id, type: ObjectIdentifier(AccessibilityAdjustment.self)) else { return false }
        StateDispatch.dispatching(to: id) {   // ID-F: the adjusted element
            handler(AccessibilityAdjustment(direction: direction))
        }
        setNeedsRedraw()
        return true
    }
}
