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
                        _ tree: @autoclosure () -> AccessibilityTree,
                        to platformWindow: any PlatformWindow) -> Bool {
        lastEmissionCount = emissionCount
        let dirties = retry && !lastFrameRetried
        lastFrameRetried = retry
        guard isActive else { return dirties }
        let built = tree()
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
            // The LAST hitbox for the id with a click handler, as click dispatch
            // ranks a later registration above an earlier one; then, where
            // `allowsHitTesting(false)` withheld the hitbox from an enabled
            // `onClick`, that handler (plan task 12 part 2, `IX-Z` item 1:
            // SwiftUI presses there, arm B6 — a click still finds nothing).
            guard let id = node.base as? GlobalElementID,
                  let onClick = lastHitboxes.last(where: { $0.id == id && $0.handlers.onClick != nil })?
                      .handlers.onClick ?? lastAccessibilityPressOnly[id] else { return false }
            // A press runs what a click runs, with no modifiers (`DD-Z` item 9),
            // and keeps its focus request (`IX-Z` item 2).
            runClick(onClick, on: id, modifiers: [])
            setNeedsRedraw()
            return true
        case .increment(let node):
            return adjust(node, .increment)
        case .decrement(let node):
            return adjust(node, .decrement)
        case .focus(let node):
            // `Window.focus` itself validates nothing; the refusal here is what
            // keeps a client from focusing an element that ignores keystrokes.
            guard let id = node.base as? GlobalElementID,
                  lastFocusRegistry.isFocusable(id) else { return false }
            focus(id)
            return true
        case .customAction:
            // Lane 2 (`IX-Y`) replaces this arm with the node's named action or
            // a combined node's redirect; until then a custom action is refused
            // exactly as an unknown id is.
            return false
        case .select(let row):
            // The row's table in the last published tree (`IX-AA` item 1).
            guard let table = accessibility.lastPublished.nodes.first(where: {
                $0.value.role == .table && $0.value.children.contains(row)
            })?.key else { return false }
            return selectRows(table, [row])
        case .selectRows(let table, let rows):
            return selectRows(table, rows)
        }
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
        guard let id = node.base as? GlobalElementID,
              let handler = lastFocusRegistry.actionHandler(
                  for: id, type: ObjectIdentifier(AccessibilityAdjustment.self)) else { return false }
        StateDispatch.dispatching(to: id) {   // ID-F: the adjusted element
            handler(AccessibilityAdjustment(direction: direction))
        }
        setNeedsRedraw()
        return true
    }
}
