import CAccessKit
import Foundation
import MetalUIPlatform
import SDLBridge

/// One window's AccessKit adapter (ruling AX-C): AT-SPI on Linux, UI
/// Automation on Windows, NSAccessibility on macOS, all from the same
/// ``AccessKitSnapshot``.
///
/// AccessKit asks for the tree when a screen reader appears and sends
/// actions back — on Linux from its own thread. So the snapshot and the
/// queue of actions sit behind a lock, the callbacks only read the one and
/// append to the other, and the main thread drains the queue in
/// ``SDLPlatform/pumpEvents()`` (woken through `mui_wake_for_accessibility`).
final class AccessKitAdapter: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: AccessKitSnapshot
    private var queued: [Queued] = []
    private let windowID: UInt32
    private var adapter: OpaquePointer?

    enum Queued: Equatable {
        case activate
        case action(AccessKitSnapshot.Action, UInt64)
    }

    /// `nativeWindow` is `mui_window_native_handle`'s answer — required on
    /// macOS and Windows, ignored on Linux (AT-SPI needs no window handle).
    init(windowID: UInt32, title: String, nativeWindow: UnsafeMutableRawPointer?) {
        self.windowID = windowID
        snapshot = .empty(title: title)
        let me = Unmanaged.passUnretained(self).toOpaque()
        #if os(Linux)
        adapter = accesskit_unix_adapter_new(Self.activation, me, Self.action, me, Self.deactivation, me)
        #elseif os(macOS)
        if let nativeWindow {
            Self.installFocusForwarder
            adapter = accesskit_macos_subclassing_adapter_for_window(nativeWindow, Self.activation, me,
                                                                     Self.action, me)
        }
        #elseif os(Windows)
        if let nativeWindow {
            adapter = accesskit_windows_subclassing_adapter_new(unsafeBitCast(nativeWindow, to: HWND.self), Self.activation, me,
                                                                Self.action, me)
        }
        #endif
    }

    deinit {
        #if os(Linux)
        if let adapter { accesskit_unix_adapter_free(adapter) }
        #elseif os(macOS)
        if let adapter { accesskit_macos_subclassing_adapter_free(adapter) }
        #elseif os(Windows)
        if let adapter { accesskit_windows_subclassing_adapter_free(adapter) }
        #endif
    }

    /// Whether the platform's adapter exists — false on macOS or Windows when
    /// SDL gave no native window.
    var isConnected: Bool { adapter != nil }

    /// Replaces the tree and, if a screen reader is listening, sends it.
    func publish(_ next: AccessKitSnapshot) {
        lock.lock()
        let changed = snapshot != next
        snapshot = next
        lock.unlock()
        guard changed, let adapter else { return }
        let me = Unmanaged.passUnretained(self).toOpaque()
        #if os(Linux)
        accesskit_unix_adapter_update_if_active(adapter, Self.factory, me)
        #elseif os(macOS)
        if let events = accesskit_macos_subclassing_adapter_update_if_active(adapter, Self.factory, me) {
            accesskit_macos_queued_events_raise(events)
        }
        #elseif os(Windows)
        if let events = accesskit_windows_subclassing_adapter_update_if_active(adapter, Self.factory, me) {
            accesskit_windows_queued_events_raise(events)
        }
        #endif
    }

    /// The window's frame on screen, in physical pixels — AT-SPI has no
    /// window handle to ask, so Linux is told (`set_root_window_bounds`).
    func setWindowBounds(x: Double, y: Double, width: Double, height: Double) {
        #if os(Linux)
        guard let adapter else { return }
        let rect = accesskit_rect(x0: x, y0: y, x1: x + width, y1: y + height)
        accesskit_unix_adapter_set_root_window_bounds(adapter, rect, rect)
        #endif
    }

    func setFocused(_ focused: Bool) {
        #if os(Linux)
        guard let adapter else { return }
        accesskit_unix_adapter_update_window_focus_state(adapter, focused)
        #endif
    }

    /// Everything the callbacks queued since the last drain, oldest first.
    func drain() -> [Queued] {
        lock.lock()
        defer { lock.unlock() }
        let out = queued
        queued = []
        return out
    }

    /// AccessKit's own rendering of the tree it holds (Linux only) — the one
    /// place a test can read what a screen reader would.
    var debugDescription: String? {
        #if os(Linux)
        guard let adapter, let text = accesskit_unix_adapter_debug(adapter) else { return nil }
        defer { accesskit_string_free(text) }
        return String(cString: text)
        #else
        return nil
        #endif
    }

    // MARK: - Callbacks (any thread)

    func enqueueForTesting(_ item: Queued) { enqueue(item) }

    fileprivate func enqueue(_ item: Queued) {
        lock.lock()
        queued.append(item)
        lock.unlock()
        _ = mui_wake_for_accessibility(windowID)
    }

    fileprivate func currentUpdate() -> OpaquePointer {
        lock.lock()
        let current = snapshot
        lock.unlock()
        return Self.treeUpdate(current)
    }

    private static let factory: accesskit_tree_update_factory = { userdata in
        Unmanaged<AccessKitAdapter>.fromOpaque(userdata!).takeUnretainedValue().currentUpdate()
    }

    private static let activation: accesskit_activation_handler_callback = { userdata in
        let me = Unmanaged<AccessKitAdapter>.fromOpaque(userdata!).takeUnretainedValue()
        me.enqueue(.activate)
        return me.currentUpdate()
    }

    private static let action: accesskit_action_handler_callback = { request, userdata in
        guard let request else { return }
        defer { accesskit_action_request_free(request) }
        let me = Unmanaged<AccessKitAdapter>.fromOpaque(userdata!).takeUnretainedValue()
        guard let action = AccessKitSnapshot.action(request.pointee.action) else { return }
        me.enqueue(.action(action, request.pointee.target_node))
    }

    private static let deactivation: accesskit_deactivation_handler_callback = { _ in }

    #if os(macOS)
    /// SDL's `NSWindow` subclass must forward focus to the adapter's view;
    /// AccessKit patches the class once per process.
    private static let installFocusForwarder: Void = {
        accesskit_macos_add_focus_forwarder_to_window_class("SDL3Window")
    }()
    #endif

    // MARK: - Snapshot → C

    /// A full `accesskit_tree_update` for `snapshot`; ownership passes to
    /// AccessKit.
    static func treeUpdate(_ snapshot: AccessKitSnapshot) -> OpaquePointer {
        let update = accesskit_tree_update_with_capacity_and_focus(snapshot.nodes.count, snapshot.focus)!
        accesskit_tree_update_set_tree_info(update, accesskit_tree_info_new(AccessKitSnapshot.rootID))
        for node in snapshot.nodes {
            let out = accesskit_node_new(role(node.role))!
            if let label = node.label { accesskit_node_set_label(out, label) }
            if let value = node.value { accesskit_node_set_value(out, value) }
            if let (x0, y0, x1, y1) = node.bounds {
                accesskit_node_set_bounds(out, accesskit_rect(x0: x0, y0: y0, x1: x1, y1: y1))
            }
            node.children.withUnsafeBufferPointer {
                accesskit_node_set_children(out, $0.count, $0.baseAddress)
            }
            for action in node.actions.sorted(by: { code($0) < code($1) }) {
                accesskit_node_add_action(out, code(action))
            }
            if node.isDisabled { accesskit_node_set_disabled(out) }
            if node.isSelected { accesskit_node_set_selected(out, true) }
            accesskit_tree_update_push_node(update, node.id, out)
        }
        return update
    }

    static func role(_ role: AccessKitSnapshot.Role) -> UInt8 {
        let value = switch role {
        case .window: ACCESSKIT_ROLE_WINDOW.rawValue
        case .genericContainer: ACCESSKIT_ROLE_GENERIC_CONTAINER.rawValue
        case .button: ACCESSKIT_ROLE_BUTTON.rawValue
        case .label: ACCESSKIT_ROLE_LABEL.rawValue
        case .image: ACCESSKIT_ROLE_IMAGE.rawValue
        case .table: ACCESSKIT_ROLE_TABLE.rawValue
        case .row: ACCESSKIT_ROLE_ROW.rawValue
        }
        return UInt8(value)
    }

    static func code(_ action: AccessKitSnapshot.Action) -> UInt8 {
        let value = switch action {
        case .click: ACCESSKIT_ACTION_CLICK.rawValue
        case .focus: ACCESSKIT_ACTION_FOCUS.rawValue
        case .increment: ACCESSKIT_ACTION_INCREMENT.rawValue
        case .decrement: ACCESSKIT_ACTION_DECREMENT.rawValue
        }
        return UInt8(value)
    }
}

extension AccessKitSnapshot {
    /// The snapshot action an AccessKit action code means, if MetalUI has one.
    static func action(_ code: UInt8) -> Action? {
        [Action.click, .focus, .increment, .decrement].first { AccessKitAdapter.code($0) == code }
    }
}
