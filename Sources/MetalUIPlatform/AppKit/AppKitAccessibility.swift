#if os(macOS)
import AppKit
import MetalUICore

// The AppKit half of the accessibility bridge (spec
// `docs/superpowers/specs/2026-09-15-accessibility-bridge-design.md`, lane 2;
// rulings AB-B, AB-D, AB-E, AB-H, AB-J, AB-K, AB-L, AB-N, AB-W, AB-X, AB-AB,
// AB-AC in `docs/superpowers/2026-09-15-accessibility-bridge-decisions.md`).
//
// **Shape.** `Window` pushes an `AccessibilityTree` value per changed frame
// through `AppKitWindow.publishAccessibilityTree`, which lands in
// `AppKitAccessibilityBridge.publish`. The host view (`MetalHostView`) is an
// `AXGroup` whose children, hit test and focused element come from the bridge.
// Every other node is an `AppKitAccessibilityElement` the bridge creates **the
// first time a client is handed it** and keeps per `AccessibilityNodeID` for as
// long as the id stays published. Every attribute is read from the bridge's
// current tree at query time; nothing is copied into an element on publish.
//
// **Ownership (AB-D).** `AppKitWindow` and the host view hold the bridge
// strongly; the bridge holds the host view weakly and its vended elements
// strongly until they detach; an element holds the bridge weakly. A detached
// element is retained only by whichever client still holds it.

/// Runs `body` with `object` on the main actor when called on the main thread,
/// and answers `fallback` without running it anywhere else (ruling AB-AE).
///
/// **Why every override needs it.** AppKit's `NSAccessibility` protocol and
/// `NSAccessibilityElement` carry no main-actor annotation, so every override
/// below — on `MetalHostView` too — is **nonisolated**, and a body reading the
/// bridge's `@MainActor` tree warns. The committed overrides probe typechecked
/// constant bodies and could not see it
/// (`docs/probes/appkit-accessibility-override-isolation-typecheck.swift`).
///
/// **Why a fallback, not a trap or a hop.** An out-of-process client's hit test
/// arrived on the main thread in all three runs of
/// `docs/probes/appkit-accessibility-override-isolation.swift`'s arm B, so the
/// fallback is expected to be unreachable. But that arm observed one entry
/// point, nothing documents the rest, `MainActor.assumeIsolated` alone
/// would trap if it were reached (CLAUDE.md's SIGTRAP history), and
/// `DispatchQueue.main.sync` would deadlock against a main thread waiting on
/// the caller. So an off-main query is answered "nothing": no element, no
/// action, no activation. `anOffMainThreadQueryAnswersNothingAndDoesNotTrap`
/// pins it.
///
/// **The box.** `assumeIsolated` requires a `Sendable` result and an override
/// returns `Any?`; `MainThreadAnswer` is built and unwrapped on the main thread,
/// so its `@unchecked Sendable` is never exercised across threads.
///
/// **Why `object` is a parameter.** A body capturing `self` from the nonisolated
/// override is rejected (`sending 'self' risks causing data races`, arm A's
/// `-D CAPTURE`); handing it in boxed is not.
nonisolated func mainActorAnswer<Object: AnyObject, T>(_ object: Object, fallback: T,
                                                      _ body: @MainActor (Object) -> T) -> T {
    guard Thread.isMainThread else { return fallback }
    let boxed = MainThreadAnswer(value: object)
    return MainActor.assumeIsolated { MainThreadAnswer(value: body(boxed.value)) }.value
}

/// See `mainActorAnswer(_:fallback:_:)`.
struct MainThreadAnswer<T>: @unchecked Sendable { let value: T }

/// Posts NSAccessibility notifications. A seam so tests can record what is
/// posted without an AX server.
@MainActor protocol AccessibilityNotificationPosting: AnyObject {
    func post(_ notification: NSAccessibility.Notification, for element: Any)
}

@MainActor final class SystemAccessibilityNotificationPoster: AccessibilityNotificationPosting {
    func post(_ notification: NSAccessibility.Notification, for element: Any) {
        NSAccessibility.post(element: element, notification: notification)
    }
}

/// Whether a screen reader is known to be running: the bridge's second
/// activation trigger (AB-B).
@MainActor protocol AccessibilityClientSignal: AnyObject {
    /// Calls `handler` with the current value **before returning**, then on
    /// every change, possibly after a main-actor hop (AB-AB).
    func observe(_ handler: @escaping @MainActor (Bool) -> Void)
}

/// `NSWorkspace.isVoiceOverEnabled`, observed.
///
/// **Exactly the spelling `docs/probes/appkit-voiceover-signal-isolation.swift`
/// typechecks with zero `warning:` lines** (AB-AB). The initial value is read
/// and delivered synchronously, AFTER the observation is installed, so a flip
/// between the two arrives late rather than being lost. A later change hops to
/// the main actor through a `Task` carrying only a `Bool`. Two spellings that
/// look simpler are wrong: `.initial` with the handler called inside the KVO
/// closure warns `[#ActorIsolatedCall]` (and `-warnings-as-errors` still exits
/// 0 on it), and `MainActor.assumeIsolated` would trap if KVO ever delivered off
/// the main thread, which nothing documents it does not.
@MainActor final class VoiceOverSignal: AccessibilityClientSignal {
    private var observation: NSKeyValueObservation?

    func observe(_ handler: @escaping @MainActor (Bool) -> Void) {
        observation = NSWorkspace.shared.observe(\.isVoiceOverEnabled, options: [.new]) { _, change in
            let value = change.newValue ?? false
            Task { @MainActor in handler(value) }
        }
        handler(NSWorkspace.shared.isVoiceOverEnabled)
    }
}

@MainActor final class AppKitAccessibilityBridge {
    weak var hostView: NSView?
    var poster: any AccessibilityNotificationPosting

    /// The window's request handler (`PlatformWindow.onAccessibilityRequest`).
    ///
    /// **Assigning it delivers a pending activation, once** (AB-B). The signal
    /// reports a running screen reader inside this bridge's initializer, which
    /// `AppKitWindow.init` runs before `Window.init` assigns this handler: at
    /// that moment nobody is listening, so the bridge records `isActive` and
    /// sends the `.activate` here, synchronously, with no run-loop turn.
    var onRequest: ((AccessibilityRequest) -> Bool)? {
        didSet {
            guard activationIsPending, let onRequest else { return }
            activationIsPending = false
            _ = onRequest(.activate)
        }
    }

    /// Retained: `VoiceOverSignal` owns the KVO observation.
    private let signal: any AccessibilityClientSignal

    /// Set by the first trigger and never cleared (AB-B).
    private(set) var isActive = false
    private var activationIsPending = false

    /// The last published tree. Stored on every publish, active or not.
    private(set) var tree = AccessibilityTree.empty

    /// Only elements a client has been handed (AB-X). Never pre-populated, and
    /// an element leaves this map exactly when it detaches.
    private(set) var elements: [AccessibilityNodeID: AppKitAccessibilityElement] = [:]

    /// Child → parent over `tree`, rebuilt on a structural publish only.
    private(set) var parents: [AccessibilityNodeID: AccessibilityNodeID] = [:]

    /// Whether a client read a children list, a hit test or the focused element
    /// since the last `.layoutChanged` (AB-K's coalescing). The activating query
    /// counts.
    private var clientHasReadSinceLayoutChanged = false

    /// Elements ever created. Test observable (AB-M).
    private(set) var createdElementCount = 0
    /// Publishes, while active, whose structure differed. Test observable.
    private(set) var structuralPublishCount = 0
    /// Publishes, while active, that changed geometry at most. Test observable.
    private(set) var geometryPublishCount = 0

    init(signal: any AccessibilityClientSignal, poster: any AccessibilityNotificationPosting) {
        self.signal = signal
        self.poster = poster
        // Synchronous for the current value (AB-AB): a window opened under a
        // running screen reader is active before this initializer returns.
        signal.observe { [weak self] running in
            if running { self?.activateIfNeeded() }
        }
    }

    /// Sends `.activate` the first time, or parks it until `onRequest` is
    /// assigned. Every later call is a no-op: activation is sticky.
    func activateIfNeeded() {
        guard !isActive else { return }
        isActive = true
        if let onRequest {
            _ = onRequest(.activate)
        } else {
            activationIsPending = true
        }
    }

    /// A client read something whose answer a later structural change could
    /// invalidate: arms one `.layoutChanged`.
    func noteClientRead() { clientHasReadSinceLayoutChanged = true }

    /// Replaces the tree clients read (AB-K).
    ///
    /// 1. Same structure (only geometry differs): store it and return. **No
    ///    element is touched and nothing is posted**; frames are read lazily.
    /// 2. Otherwise store it and rebuild `parents`. Before activation, return.
    /// 3. Diff, then post in this order: one `.uiElementDestroyed` per removed
    ///    id that had a vended element (detaching it); one `.layoutChanged` on
    ///    the host if the structure changed and a client read since the last
    ///    one; `.titleChanged` / `.valueChanged` / `.rowCountChanged` per changed
    ///    id with a vended element; one `.focusedUIElementChanged` on the new
    ///    focus (vending it), or on the host when focus clears. Nothing for a
    ///    created id.
    func publish(_ new: AccessibilityTree) {
        let old = tree
        tree = new
        if new.hasSameStructure(as: old) {
            if isActive { geometryPublishCount += 1 }
            return
        }
        rebuildParents()
        guard isActive else { return }
        structuralPublishCount += 1

        let changes = AccessibilityTreeChanges(from: old, to: new)
        for id in changes.removed {
            guard let element = elements.removeValue(forKey: id), let last = old.nodes[id] else { continue }
            element.detach(lastNode: last, lastGeometry: old.geometry[id])
            poster.post(.uiElementDestroyed, for: element)
        }
        if changes.structureChanged, clientHasReadSinceLayoutChanged, let hostView {
            clientHasReadSinceLayoutChanged = false
            poster.post(.layoutChanged, for: hostView)
        }
        for id in changes.labelChanged { if let element = elements[id] { poster.post(.titleChanged, for: element) } }
        for id in changes.valueChanged { if let element = elements[id] { poster.post(.valueChanged, for: element) } }
        for id in changes.rowCountChanged {
            if let element = elements[id] { poster.post(.rowCountChanged, for: element) }
        }
        if changes.focusChanged {
            if let focused = new.focused, new.nodes[focused] != nil {
                poster.post(.focusedUIElementChanged, for: element(for: focused))
            } else if let hostView {
                poster.post(.focusedUIElementChanged, for: hostView)
            }
        }
    }

    private func rebuildParents() {
        parents.removeAll(keepingCapacity: true)
        for (id, node) in tree.nodes {
            for child in node.children { parents[child] = id }
        }
    }

    /// The element for a published id, created and kept the first time it is
    /// asked for. **Only a client read or a focus post calls this** (AB-X):
    /// `publish` never creates an element for any other reason.
    func element(for id: AccessibilityNodeID) -> AppKitAccessibilityElement {
        if let existing = elements[id] { return existing }
        let created = AppKitAccessibilityElement(id: id, bridge: self)
        elements[id] = created
        createdElementCount += 1
        return created
    }

    /// The roots' elements, in published order. Reading does not activate;
    /// the host view's override does that.
    func rootElements() -> [Any] { tree.roots.map { element(for: $0) } }

    /// The published element whose **visible** frame contains `screenPoint`
    /// with the greatest `(layer, order)` — click dispatch's own ranking — or
    /// `nil` when none does (AB-W). An unclipped frame never ranks: a `List`'s
    /// overscan rows lie inside the list's frame and outside what anyone can see.
    func hitTest(screenPoint: NSPoint) -> Any? {
        guard let hostView, let window = hostView.window else { return nil }
        let local = hostView.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let x = Float(local.x), y = Float(local.y)
        var best: (id: AccessibilityNodeID, layer: Int, order: Int)?
        for (id, geometry) in tree.geometry {
            let visible = geometry.visibleFrame
            guard x >= visible.origin.x.value, x < visible.origin.x.value + visible.size.width.value,
                  y >= visible.origin.y.value, y < visible.origin.y.value + visible.size.height.value
            else { continue }
            if let current = best, (current.layer, current.order) >= (geometry.layer, geometry.order) { continue }
            best = (id, geometry.layer, geometry.order)
        }
        return best.map { element(for: $0.id) }
    }

    /// The focused element, or `nil` before activation or when nothing is
    /// focused — the host view then answers itself (AB-J's recorded divergence:
    /// SwiftUI reports its first focusable node).
    func focusedElement() -> Any? {
        guard isActive, let focused = tree.focused, tree.nodes[focused] != nil else { return nil }
        return element(for: focused)
    }

    /// `rect`, in the host view's content space, converted to screen coordinates
    /// **now** (AB-E): a window move publishes nothing, so nothing screen-space
    /// may be stored. The host view is flipped, so `convert(_:to:)` does the
    /// flip. `.zero` once the host view or its window is gone.
    func screenFrame(forContentRect rect: Bounds<Pixels>) -> NSRect {
        guard let hostView, let window = hostView.window else { return .zero }
        let local = NSRect(x: CGFloat(rect.origin.x.value), y: CGFloat(rect.origin.y.value),
                           width: CGFloat(rect.size.width.value), height: CGFloat(rect.size.height.value))
        return window.convertToScreen(hostView.convert(local, to: nil))
    }
}

/// One published node, as a client holds it.
///
/// **Attached**, it answers every attribute from its bridge's current tree.
/// **Detached** — its id left the tree (AB-D) — it has no parent and no
/// children, refuses every action, and keeps describing what it last was: its
/// last role, label and value, and its last content rect converted through the
/// host view while that view is alive (probe arm 12). A detached element is
/// never reattached; an id that returns gets a new object.
///
/// **Two layers.** Each NSAccessibility override is nonisolated (AppKit's
/// protocol is) and does one thing: hand `self` to `mainActorAnswer`, which runs
/// the matching `@MainActor` method below on the main thread (AB-AE). The logic
/// lives in those methods.
@MainActor final class AppKitAccessibilityElement: NSAccessibilityElement {
    let id: AccessibilityNodeID
    weak var bridge: AppKitAccessibilityBridge?
    private(set) var lastNode: AccessibilityNode
    private(set) var lastGeometry: AccessibilityGeometry
    private(set) var isDetached = false

    init(id: AccessibilityNodeID, bridge: AppKitAccessibilityBridge) {
        self.id = id
        self.bridge = bridge
        let zero = Bounds(origin: Point(x: Pixels(0), y: Pixels(0)), size: Size(width: Pixels(0), height: Pixels(0)))
        lastNode = bridge.tree.nodes[id] ?? AccessibilityNode(role: .group)
        lastGeometry = bridge.tree.geometry[id] ?? AccessibilityGeometry(frame: zero, visibleFrame: zero)
        super.init()
    }

    /// Called by the bridge on the first publish without this id, with the
    /// last tree's values for it.
    func detach(lastNode: AccessibilityNode, lastGeometry: AccessibilityGeometry?) {
        isDetached = true
        self.lastNode = lastNode
        if let lastGeometry { self.lastGeometry = lastGeometry }
    }

    /// The live node while attached, else the last one.
    var node: AccessibilityNode {
        guard !isDetached, let live = bridge?.tree.nodes[id] else { return lastNode }
        return live
    }

    private var liveBridge: AppKitAccessibilityBridge? { isDetached ? nil : bridge }

    // MARK: Overrides (nonisolated; AB-AE)

    override func accessibilityRole() -> NSAccessibility.Role? { mainActorAnswer(self, fallback: nil) { $0.role } }
    override func accessibilityLabel() -> String? { mainActorAnswer(self, fallback: nil) { $0.node.label } }
    override func accessibilityValue() -> Any? { mainActorAnswer(self, fallback: nil) { $0.node.value } }
    override func isAccessibilityElement() -> Bool { true }
    override func isAccessibilityEnabled() -> Bool { mainActorAnswer(self, fallback: false) { $0.node.isEnabled } }
    override func isAccessibilitySelected() -> Bool { mainActorAnswer(self, fallback: false) { $0.node.isSelected } }
    override func accessibilityParent() -> Any? { mainActorAnswer(self, fallback: nil) { $0.parent } }
    override func accessibilityChildren() -> [Any]? { mainActorAnswer(self, fallback: []) { $0.children } }
    override func accessibilityFrame() -> NSRect { mainActorAnswer(self, fallback: .zero) { $0.screenFrame } }
    override func accessibilityRowCount() -> Int { mainActorAnswer(self, fallback: 0) { $0.node.rowCount ?? 0 } }
    override func accessibilityRows() -> [Any]? { mainActorAnswer(self, fallback: []) { $0.rows(visibleOnly: false) } }
    override func accessibilityVisibleRows() -> [Any]? {
        mainActorAnswer(self, fallback: []) { $0.rows(visibleOnly: true) }
    }
    override func accessibilityIndex() -> Int { mainActorAnswer(self, fallback: 0) { $0.node.rowIndex ?? 0 } }
    override func isAccessibilityFocused() -> Bool { mainActorAnswer(self, fallback: false) { $0.isFocused } }
    override func setAccessibilityFocused(_ focused: Bool) {
        mainActorAnswer(self, fallback: ()) { $0.requestFocus(focused) }
    }
    override func accessibilityPerformPress() -> Bool {
        mainActorAnswer(self, fallback: false) { $0.perform(.press, .press($0.id)) }
    }
    override func accessibilityPerformIncrement() -> Bool {
        mainActorAnswer(self, fallback: false) { $0.perform(.increment, .increment($0.id)) }
    }
    override func accessibilityPerformDecrement() -> Bool {
        mainActorAnswer(self, fallback: false) { $0.perform(.decrement, .decrement($0.id)) }
    }
    override func isAccessibilitySelectorAllowed(_ selector: Selector) -> Bool {
        let answer: Bool? = mainActorAnswer(self, fallback: false) { $0.allows(selector) }
        return answer ?? super.isAccessibilitySelectorAllowed(selector)
    }

    // MARK: Answers (main actor)

    private var role: NSAccessibility.Role {
        switch node.role {
        case .group: .group
        case .button: .button
        case .staticText: .staticText
        case .image: .image
        case .table: .table
        case .row: .row
        }
    }

    /// The parent node's element, or the host view for a root; `nil` detached.
    private var parent: Any? {
        guard let bridge = liveBridge else { return nil }
        if let parent = bridge.parents[id] { return bridge.element(for: parent) }
        return bridge.hostView
    }

    private var children: [Any] {
        guard let bridge = liveBridge else { return [] }
        bridge.noteClientRead()
        return node.children.map { bridge.element(for: $0) }
    }

    /// Converted now, from the live geometry while attached and from the last
    /// geometry once detached (AB-D, AB-E).
    private var screenFrame: NSRect {
        guard let bridge else { return .zero }
        if !isDetached, let geometry = bridge.tree.geometry[id] {
            return bridge.screenFrame(forContentRect: geometry.frame)
        }
        return bridge.screenFrame(forContentRect: lastGeometry.frame)
    }

    /// A table's `.row` children (AB-L); with `visibleOnly`, those whose visible
    /// frame has area — a realized overscan row scrolled out of the viewport is
    /// a row, and not a visible one. A row's `accessibilityIndex` is its logical
    /// index, and a table's `accessibilityRowCount` its logical count, not
    /// anything counted here.
    private func rows(visibleOnly: Bool) -> [Any] {
        guard let bridge = liveBridge, node.role == .table else { return [] }
        bridge.noteClientRead()
        return node.children.filter { child in
            guard bridge.tree.nodes[child]?.role == .row else { return false }
            guard visibleOnly else { return true }
            let visible = bridge.tree.geometry[child]?.visibleFrame
            return (visible?.size.width.value ?? 0) > 0 && (visible?.size.height.value ?? 0) > 0
        }.map { bridge.element(for: $0) }
    }

    private var isFocused: Bool {
        guard let bridge = liveBridge else { return false }
        return bridge.tree.focused == id
    }

    /// `true` asks the window to move keyboard focus here, and the window
    /// refuses an element the last frame did not find focusable; the element
    /// reports the new focus once the next frame publishes it (AB-J). `false` is
    /// ignored: `Window.focus` has no "unfocus this one".
    private func requestFocus(_ focused: Bool) {
        guard focused, let bridge = liveBridge else { return }
        _ = bridge.onRequest?(.focus(id))
    }

    /// A disallowed action returns `false` without sending anything; an allowed
    /// one returns the window's answer (AB-H).
    private func perform(_ action: AccessibilityActions, _ request: AccessibilityRequest) -> Bool {
        guard allows(action), let onRequest = bridge?.onRequest else { return false }
        return onRequest(request)
    }

    private func allows(_ action: AccessibilityActions) -> Bool {
        liveBridge != nil && node.actions.contains(action)
    }

    /// Per instance, from the node's derived actions (AB-H): an element never
    /// advertises an action no live handler backs, and a detached one none at
    /// all. Table and row attributes are offered only by tables and rows.
    /// `nil` defers to `NSAccessibilityElement`'s answer.
    private func allows(_ selector: Selector) -> Bool? {
        switch selector {
        case #selector(NSAccessibilityElement.accessibilityPerformPress): allows(.press)
        case #selector(NSAccessibilityElement.accessibilityPerformIncrement): allows(.increment)
        case #selector(NSAccessibilityElement.accessibilityPerformDecrement): allows(.decrement)
        case #selector(NSAccessibilityElement.accessibilityRowCount),
             #selector(NSAccessibilityElement.accessibilityRows),
             #selector(NSAccessibilityElement.accessibilityVisibleRows):
            node.role == .table
        case #selector(NSAccessibilityElement.accessibilityIndex): node.role == .row
        default: nil
        }
    }
}

/// The host view is an `AXGroup` element whose children are the published
/// roots (AB-N).
///
/// **What activates (AB-B).** `accessibilityChildren` and `accessibilityHitTest`
/// send `.activate` (once, through the bridge). `accessibilityFocusedUIElement`
/// does NOT: it is the query a focus-polling utility with no screen reader
/// makes from another process (measured,
/// `docs/probes/appkit-accessibility-activation-clients.swift`), and as a
/// trigger it would turn on per-frame collection for users who run none.
///
/// Nonisolated overrides, as on the element (AB-AE).
extension MetalHostView {
    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .group }

    override func accessibilityChildren() -> [Any]? {
        mainActorAnswer(self, fallback: []) { host in
            guard let bridge = host.accessibilityBridge else { return [] }
            bridge.activateIfNeeded()
            bridge.noteClientRead()
            return bridge.rootElements()
        }
    }

    /// Before activation this activates and answers the host view: the window
    /// has published nothing yet.
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        mainActorAnswer(self, fallback: nil) { host in
            guard let bridge = host.accessibilityBridge else { return host }
            let wasActive = bridge.isActive
            bridge.activateIfNeeded()
            bridge.noteClientRead()
            guard wasActive else { return host }
            return bridge.hitTest(screenPoint: point) ?? host
        }
    }

    override var accessibilityFocusedUIElement: Any? {
        mainActorAnswer(self, fallback: nil) { host in
            guard let bridge = host.accessibilityBridge else { return host }
            bridge.noteClientRead()
            return bridge.focusedElement() ?? host
        }
    }
}
#endif
